//
//  QSPurchase.swift
//  QSInAppPurchase
//
//  Created by MacM2 on 12/4/25.
//

import StoreKit

// 过期时间
private let kExpirationTimestampKey = "kExpirationTimestampKey"

@MainActor
public class QSPurchase {
    // MARK: - Func
    
    /// 获取产品
    public func getProducts(productIds: [String], onSuccess: ([Product]) -> Void, onFailure: (String) -> Void) async {
        if !products.isEmpty {
            // 在已有 products 中筛选出对应的 productIds
            let filtered = products.filter { product in
                productIds.contains(product.id)
            }
            
            // 按照 productIds 的顺序排序
            let sorted = productIds.compactMap { id in
                filtered.first { $0.id == id }
            }
            
            // 判断是否包含所有 productIds
            if sorted.count == productIds.count {
                onSuccess(sorted)
                return
            }
        }
        
        do {
            let tempProducts = try await Product.products(for: productIds)
            // 按照 productIds 的顺序排序
            let sorted = productIds.compactMap { id in
                tempProducts.first { $0.id == id }
            }
            products = sorted
            onSuccess(products)
        } catch {
            onFailure(error.localizedDescription)
        }
    }
    
    /// 购买产品
    public func requestPurchase(product: Product,
                                onSuccess: @escaping ((_ purchaseID: String, _ subscriptionDate: String) -> Void),
                                onFailure: @escaping ((_ error: String) -> Void),
                                onCancel: () -> Void) async
    {
        purchaseSuccess = onSuccess
        purchaseFailure = onFailure
        
        do {
            let result = try await product.purchase()
            switch result {
                case let .success(transactionResult):
                    await verifyTransaction(result: transactionResult)
                    
                case .userCancelled:
                    onCancel()
                    
                case .pending:
                    break
                    
                @unknown default:
                    break
            }
        } catch {
            onFailure(error.localizedDescription)
            
            purchaseSuccess = nil
            purchaseFailure = nil
            restoreSuccess = nil
            restoreFailure = nil
        }
    }
    
    /// 恢复购买
    public func restorePurchase() async {
        try? await AppStore.sync()
    }
    
    /// 校验交易订单
    public func checkTransactions(onSuccess: () -> Void, onFailure: () -> Void) async {
        for await result in Transaction.currentEntitlements {
            await verifyTransaction(result: result)
        }
        
        if isVip {
            onSuccess()
        } else {
            onFailure()
        }
    }
    
    /// 通过id获取商品
    public func getProduct(by id: String) -> Product? {
        return products.first { product in
            return product.id == id
        }
    }
    
    /// 监听交易更新
    private func listenForTransactions() async {
        // 启动时进行校验
        var hasTransaction = false
        for await result in Transaction.currentEntitlements {
            hasTransaction = true
            await verifyTransaction(result: result)
        }
        if !hasTransaction {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.vipAction?(false)
            }
        }
        
        // 持续监听交易更新
        for await result in Transaction.updates {
            await verifyTransaction(result: result)
        }
    }
    
    /// 校验交易
    private func verifyTransaction(result: VerificationResult<Transaction>) async {
        switch result {
                // 已验证的交易
            case let .verified(transaction):
                // 结束交易
                await transaction.finish()
                
                // 商品类型是否是续订类型
                if transaction.productType == .autoRenewable {
                    // 免费期间
                    if (transaction.price ?? 0) <= 0 {
                        // 是否取消续订
                        if let info = await transaction.subscriptionStatus?.renewalInfo {
                            switch info {
                                case .unverified(_, _):
                                    break
                                case .verified(let signedType):
                                    // 已经取消
                                    if !signedType.willAutoRenew {
                                        isVip = false
                                        vipAction?(isVip)
                                        cancelFreeTrialAction?()
                                        return
                                    }
                            }
                        }
                    }
                }
                
                // 判断过期时间
                if let expirationTimestamp = UserDefaults.standard.value(forKey: kExpirationTimestampKey) as? Double {
                    if expirationTimestamp > Date().timeIntervalSince1970 {
                        isVip = true
                        vipAction?(isVip)
                        return
                    }
                }
                
                // 产品类型
                let productType = transaction.productType
                switch productType {
                        // 消耗品，使用一次就没了
                    case .consumable:
                        break
                        
                        // 非消耗品，终身有效
                    case .nonConsumable:
                        if let dateIn100Years = Calendar.current.date(byAdding: .year, value: 100, to: Date()) {
                            purchaseSuccesHandler(originalID: String(transaction.originalID), originalPurchaseDate: String(transaction.originalPurchaseDate.timeIntervalSince1970 * 1000), expirationDate: dateIn100Years)
                        }
                        return
                        
                        // 自动续订
                    case .autoRenewable:
                        break
                        
                        // 非自动续订
                    case .nonRenewable:
                        break
                        
                    default:
                        break
                }
                
                // 过期时间
                if let expirationDate = transaction.expirationDate {
                    // 过期
                    if expirationDate.timeIntervalSince1970 < Date().timeIntervalSince1970 {
                        isVip = false
                        vipAction?(isVip)
                    }
                    // 未过期
                    else {
                        purchaseSuccesHandler(originalID: String(transaction.originalID), originalPurchaseDate: String(transaction.originalPurchaseDate.timeIntervalSince1970 * 1000), expirationDate: expirationDate)
                    }
                } else {
                    isVip = false
                    vipAction?(isVip)
                }
                
                // 处理未验证的交易
            case let .unverified(transaction, error):
                // 结束交易
                await transaction.finish()
                myPrint("交易验证失败: \(error)")
                isVip = false
                vipAction?(isVip)
                
                // 购买失败
                if let failure = purchaseFailure {
                    failure(error.localizedDescription)
                }
                // 恢复购买失败
                else if let failure = restoreFailure {
                    failure(error.localizedDescription)
                }
                
                purchaseSuccess = nil
                purchaseFailure = nil
                restoreSuccess = nil
                restoreFailure = nil
        }
    }
    
    /// 购买成功
    private func purchaseSuccesHandler(originalID: String, originalPurchaseDate: String, expirationDate: Date) {
        isVip = true
        vipAction?(isVip)
        
        // 保存过期时间
        let expirationTimestamp = expirationDate.timeIntervalSince1970
        UserDefaults.standard.setValue(expirationTimestamp, forKey: kExpirationTimestampKey)
        
        // 购买成功
        if let success = purchaseSuccess {
            success(originalID, originalPurchaseDate)
        }
        // 恢复购买成功
        else if let success = restoreSuccess {
            success()
        }
        
        purchaseSuccess = nil
        purchaseFailure = nil
        restoreSuccess = nil
        restoreFailure = nil
    }
    
    private func myPrint(_ items: Any...) {
#if DEBUG
        print(items)
#endif
    }
    
    // MARK: - Property
    
    // 所有产品
    private var products: [Product] = []
    private var purchaseSuccess: ((_ purchaseID: String, _ subscriptionDate: String) -> Void)?
    private var purchaseFailure: ((_ error: String) -> Void)?
    private var restoreSuccess: (() -> Void)?
    private var restoreFailure: ((_ error: String) -> Void)?
    
    private var isVip = false
    public var vipAction: ((Bool) -> Void)?
    public var cancelFreeTrialAction: (() -> Void)?
    
    // MARK: - Singleton
    
    public static let shared = QSPurchase()
    private init() {
        // 监听交易更新
        Task {
            await listenForTransactions()
        }
    }
}

