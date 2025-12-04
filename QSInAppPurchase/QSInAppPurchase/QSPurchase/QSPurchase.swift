//
//  QSPurchase.swift
//  QSInAppPurchase
//
//  Created by MacM2 on 12/4/25.
//

import StoreKit

// 过期时间
private let kExpirationTimestampKey = "kExpirationTimestampKey"

public class QSPurchase {
    // MARK: - Func
    /// 获取产品
    func getProducts(productIds: [String], onSuccess: (([Product]) -> Void), onFailure: ((String) -> Void)) async {
        if !products.isEmpty {
            // 在已有 products 中筛选出对应的 productIds
            let filtered = products.filter { product in
                return productIds.contains(product.id)
            }
            
            // 判断是否包含所有 productIds
            if filtered.count == productIds.count {
                onSuccess(filtered)
                return
            }
        }
        
        do {
            products = try await Product.products(for: productIds)
            onSuccess(products)
        } catch let error {
            onFailure(error.localizedDescription)
        }
    }
    
    /// 购买产品
    func requestPurchase(product: Product,
                         onSuccess: @escaping ((_ purchaseID: String, _ subscriptionDate: String) -> Void),
                         onFailure: @escaping ((_ error: String) -> Void),
                         onCancel: (() -> Void)) async {
        purchaseSuccess = onSuccess
        purchaseFailure = onFailure
        
        do {
            let result = try await product.purchase()
            switch result {
                case .success(let transactionResult):
                    await verifyTransaction(result: transactionResult)
                    
                case .userCancelled:
                    onCancel()
                    
                case .pending:
                    break
                    
                @unknown default:
                    break
            }
        } catch let error {
            onFailure(error.localizedDescription)
            
            purchaseSuccess = nil
            purchaseFailure = nil
            restoreSuccess = nil
            restoreFailure = nil
        }
    }
    
    /// 恢复购买
    func restorePurchase(onSuccess: (() -> Void), onFailure: (() -> Void)) async {
        for await result in Transaction.currentEntitlements {
            await verifyTransaction(result: result)
        }
        
        if isVip {
            onSuccess()
        } else {
            onFailure()
        }
    }
    
    /// 监听交易更新
    private func listenForTransactions() async {
        // 启动时进行校验
        for await result in Transaction.currentEntitlements {
            await verifyTransaction(result: result)
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
            case .verified(let transaction):
                // 结束交易
                await transaction.finish()
                
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
                let expirationDate = transaction.expirationDate
                
                // 是否有订阅
                if var expirationDate = expirationDate {
                    // 订阅过期时间，赠送两小时
                    expirationDate = Calendar.current.date(byAdding: .hour, value: 2, to: expirationDate)!
                    
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
            case .unverified(let transaction, let error):
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
    var vipAction: ((Bool) -> Void)?
    
    // MARK: - Singleton
    static let shared = QSPurchase()
    private init() {
        // 监听交易更新
        Task {
            await listenForTransactions()
        }
    }
}
