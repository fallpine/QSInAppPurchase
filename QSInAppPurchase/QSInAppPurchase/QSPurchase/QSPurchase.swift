//
//  QSPurchase.swift
//  QSInAppPurchase
//
//  Created by MacM2 on 12/4/25.
//

import StoreKit

// 过期时间
private let kExpirationTimestampKey = "kExpirationTimestampKey"
// 取消试订
private let kCancelFreeTrialKey = "kCancelFreeTrialKey"

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
                                onSuccess: @escaping ((_ productID: String,
                                                       _ transactionID: String,
                                                       _ originalTransactionID: String,
                                                       _ subscriptionDate: String,
                                                       _ originalSubscriptionDate: String,
                                                       _ price: String) -> Void),
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
    public func restorePurchase(onSuccess: @escaping () -> Void,
                                onFailure: @escaping (_ error: String) -> Void) async {
        restoreSuccess = onSuccess
        restoreFailure = onFailure
        
        
        do {
            try await AppStore.sync()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let `self` = self else { return }
                
                if !isVip {
                    onFailure("未知错误")
                }
                
                purchaseSuccess = nil
                purchaseFailure = nil
                restoreSuccess = nil
                restoreFailure = nil
            }
        } catch let e {
            onFailure(e.localizedDescription)
            
            purchaseSuccess = nil
            purchaseFailure = nil
            restoreSuccess = nil
            restoreFailure = nil
        }
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
                self?.cancelProductId = ""
                self?.updateVipState(isVip: false)
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
                // 商品类型是否是续订类型
                if transaction.productType == .autoRenewable {
                    // 免费期间
                    if (transaction.price ?? 0) <= 0 {
                        // 判断是否过去
                        if (transaction.expirationDate?.timeIntervalSince1970 ?? 0) >= Date().timeIntervalSince1970 {
                            // 是否取消续订
                            if let info = await transaction.subscriptionStatus?.renewalInfo {
                                switch info {
                                    case .unverified(_, _):
                                        break
                                    case .verified(let signedType):
                                        // 已经取消
                                        if !signedType.willAutoRenew {
                                            cancelProductId = transaction.productID
                                            updateVipState(isVip: false)
                                            
                                            if UserDefaults.standard.value(forKey: kExpirationTimestampKey) != nil &&
                                                !((UserDefaults.standard.value(forKey: kCancelFreeTrialKey) as? Bool) ?? false) {
                                                cancelFreeTrialAction?()
                                                UserDefaults.standard.removeObject(forKey: kExpirationTimestampKey)
                                            }
                                            UserDefaults.standard.setValue(true, forKey: kCancelFreeTrialKey)
                                            
                                            return
                                        }
                                }
                            }
                        }
                    }
                }
                
                // 判断过期时间
                if let expirationTimestamp = UserDefaults.standard.value(forKey: kExpirationTimestampKey) as? Double {
                    if expirationTimestamp > Date().timeIntervalSince1970 {
                        cancelProductId = ""
                        updateVipState(isVip: true)
                        return
                    }
                }
                
                // 一条交易只处理一次
                let id = String(transaction.id)
                guard !handledTransactionIDs.contains(id) else {
                    return
                }
                handledTransactionIDs.insert(id)
                // 结束交易
                await transaction.finish()
                
                // 产品类型
                let productType = transaction.productType
                switch productType {
                        // 消耗品，使用一次就没了
                    case .consumable:
                        break
                        
                        // 非消耗品，终身有效
                    case .nonConsumable:
                        if let dateIn100Years = Calendar.current.date(byAdding: .year, value: 100, to: Date()) {
                            purchaseSuccesHandler(productID: transaction.productID,
                                                  transactionID: String(transaction.id),
                                                  originalTransactionID: String(transaction.originalID),
                                                  subscriptionDate: String(transaction.purchaseDate.timeIntervalSince1970 * 1000),
                                                  originalSubscriptionDate: String(transaction.originalPurchaseDate.timeIntervalSince1970 * 1000),
                                                  price: transaction.price?.formatted() ?? "",
                                                  expirationDate: dateIn100Years)
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
                        cancelProductId = ""
                        updateVipState(isVip: false)
                    }
                    // 未过期
                    else {
                        purchaseSuccesHandler(productID: transaction.productID,
                                              transactionID: String(transaction.id),
                                              originalTransactionID: String(transaction.originalID),
                                              subscriptionDate: String(transaction.purchaseDate.timeIntervalSince1970 * 1000),
                                              originalSubscriptionDate: String(transaction.originalPurchaseDate.timeIntervalSince1970 * 1000),
                                              price: transaction.price?.formatted() ?? "",
                                              expirationDate: expirationDate)
                    }
                } else {
                    cancelProductId = ""
                    updateVipState(isVip: false)
                }
                
                // 处理未验证的交易
            case let .unverified(transaction, error):
                // 结束交易
                await transaction.finish()
                myPrint("交易验证失败: \(error)")
                cancelProductId = ""
                updateVipState(isVip: false)
                
                // 购买失败
                if let failure = purchaseFailure {
                    failure(error.localizedDescription)
                    purchaseFailure = nil
                }
                // 恢复购买失败
                else if let failure = restoreFailure {
                    failure(error.localizedDescription)
                    restoreFailure = nil
                }
        }
    }
    
    /// 购买成功
    private func purchaseSuccesHandler(productID: String,
                                       transactionID: String,
                                       originalTransactionID: String,
                                       subscriptionDate: String,
                                       originalSubscriptionDate: String,
                                       price: String,
                                       expirationDate: Date) {
        cancelProductId = ""
        updateVipState(isVip: true)
        
        // 保存过期时间
        let expirationTimestamp = expirationDate.timeIntervalSince1970
        UserDefaults.standard.setValue(expirationTimestamp, forKey: kExpirationTimestampKey)
        
        // 购买成功
        if let success = purchaseSuccess {
            success(productID,
                    transactionID,
                    originalTransactionID,
                    subscriptionDate,
                    originalSubscriptionDate,
                    price)
            purchaseSuccess = nil
        }
        // 恢复购买成功
        else if let success = restoreSuccess {
            success()
            restoreSuccess = nil
        }
    }
    
    /// 刷新vip状态
    private func updateVipState(isVip: Bool) {
        self.isVip = isVip
        vipAction?(isVip)
    }
    
    private func myPrint(_ items: Any...) {
#if DEBUG
        print(items)
#endif
    }
    
    // MARK: - Property
    private var handledTransactionIDs = Set<String>()
    // 所有产品
    private var products: [Product] = []
    private var purchaseSuccess: ((_ productID: String,
                                   _ transactionID: String,
                                   _ originalTransactionID: String,
                                   _ subscriptionDate: String,
                                   _ originalSubscriptionDate: String,
                                   _ price: String) -> Void)?
    private var purchaseFailure: ((_ error: String) -> Void)?
    private var restoreSuccess: (() -> Void)?
    private var restoreFailure: ((_ error: String) -> Void)?
    
    private var isVip = false
    public var vipAction: ((Bool) -> Void)?
    public var cancelFreeTrialAction: (() -> Void)?
    public var cancelProductId = ""
    
    // MARK: - Singleton
    
    public static let shared = QSPurchase()
    private init() {
        // 监听交易更新
        Task {
            await listenForTransactions()
        }
    }
}

