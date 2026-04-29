# QSInAppPurchase

QSInAppPurchase 是一个基于 StoreKit 2 封装的应用内购买工具，支持获取商品、发起购买、恢复购买、校验当前权益、监听会员状态变化，并提供常用的订阅价格展示字段。

当前版本：`1.2.9`

## 环境要求

- iOS 15.0+
- watchOS 10.0+
- Swift 5
- StoreKit 2

## 安装

在 `Podfile` 中添加：

```ruby
pod 'QSInAppPurchase'
```

然后执行：

```bash
pod install
```

## 快速开始

引入模块后，使用 `QSPurchase.shared` 单例：

```swift
import StoreKit
import QSInAppPurchase

let purchase = QSPurchase.shared
```

`QSPurchase` 初始化后会自动监听 StoreKit 交易更新。可以通过 `vipAction` 监听会员状态变化：

```swift
QSPurchase.shared.vipAction = { isVip in
    print("VIP 状态：\(isVip)")
}
```

## 获取商品

```swift
Task {
    await QSPurchase.shared.getProducts(
        productIds: [
            "com.example.vip.monthly",
            "com.example.vip.yearly"
        ],
        onSuccess: { products in
            print("商品列表：\(products)")
        },
        onFailure: { error in
            print("获取商品失败：\(error)")
        }
    )
}
```

获取成功后，商品会缓存在本地，可以通过商品 ID 读取：

```swift
let product = QSPurchase.shared.getProduct(by: "com.example.vip.monthly")
```

## 购买商品

```swift
Task {
    guard let product = QSPurchase.shared.getProduct(by: "com.example.vip.monthly") else {
        return
    }

    await QSPurchase.shared.requestPurchase(
        product: product,
        onSuccess: { productID, transactionID, originalTransactionID, subscriptionDate, originalSubscriptionDate, price in
            print("购买成功：\(productID)")
            print("交易 ID：\(transactionID)")
            print("原始交易 ID：\(originalTransactionID)")
            print("订阅时间：\(subscriptionDate)")
            print("原始订阅时间：\(originalSubscriptionDate)")
            print("价格：\(price)")
        },
        onFailure: { error in
            print("购买失败：\(error)")
        },
        onCancel: {
            print("用户取消购买")
        }
    )
}
```

## 恢复购买

```swift
Task {
    await QSPurchase.shared.restorePurchase(
        onSuccess: {
            print("恢复购买成功")
        },
        onFailure: { error in
            print("恢复购买失败：\(error)")
        }
    )
}
```

## 校验当前权益

可以在应用启动、进入会员页或需要刷新会员状态时调用：

```swift
Task {
    await QSPurchase.shared.checkTransactions(
        onSuccess: {
            print("当前用户拥有有效权益")
        },
        onFailure: {
            print("当前用户没有有效权益")
        }
    )
}
```

也可以直接读取当前状态：

```swift
let isVip = QSPurchase.shared.isVip
```

## 历史订单状态

`hasHistoryTransactions` 表示当前账号是否存在历史交易记录：

```swift
let hasHistoryTransactions = QSPurchase.shared.hasHistoryTransactions
```

当购买成功并刷新为 VIP 状态后，库内部会自动检查历史交易记录。

## 取消续订和取消试用

监听用户取消自动续订：

```swift
QSPurchase.shared.cancelAutoRenewAction = { productId, transactionId in
    print("用户取消续订：\(productId), \(transactionId)")
}
```

监听用户取消免费试用：

```swift
QSPurchase.shared.cancelFreeTrialAction = { productId, transactionId in
    print("用户取消试用：\(productId), \(transactionId)")
}
```

如果你的服务端处理失败，可以回滚本地记录，方便下次继续触发处理：

```swift
QSPurchase.shared.handleCancelAutoRenewFailure(id: transactionId)
QSPurchase.shared.handleCancelFreeTrialFailure(id: transactionId)
```

## Product 扩展字段

库中扩展了 StoreKit `Product` 的常用展示字段：

```swift
product.currencyPrice              // 本地化价格
product.discountCurrencyPrice      // 订阅优惠价格
product.discountRate               // 折扣比例
product.weekAveragePrice           // 每周平均价格
product.trialPeriodValue           // 试用周期数值
product.trialPeriodUnit            // 试用周期单位
product.subscriptionPeriodValue    // 订阅周期数值
product.subscriptionPeriodUnit     // 订阅周期单位
product.paymentMode                // 订阅优惠支付方式
```

## 注意事项

- 请先在 App Store Connect 中配置好内购商品 ID，并确保传入的 `productIds` 与后台配置一致。
- 真机测试前，请确认 App 已开启 In-App Purchase 能力。
- StoreKit 2 的购买、恢复、交易校验都需要在异步上下文中调用。
- `QSPurchase.shared` 创建后会自动监听交易更新。
- 购买成功后，库会保存有效期，并通过 `vipAction` 回调刷新 `isVip` 状态。

## License

QSInAppPurchase is available under the MIT license. See the LICENSE file for more info.
