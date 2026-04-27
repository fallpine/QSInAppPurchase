# QSInAppPurchase

QSInAppPurchase 是一个基于 StoreKit 2 封装的 iOS / watchOS 应用内购买工具，支持获取商品、发起购买、恢复购买、校验当前权益，并提供订阅价格、试用周期、折扣等常用字段扩展。

## 环境要求

- iOS 15.0+
- watchOS 10.0+
- Swift 5
- StoreKit 2

## 安装

使用 CocoaPods 安装：

```ruby
pod 'QSInAppPurchase'
```

然后执行：

```bash
pod install
```

## 基本使用

先引入 StoreKit，并使用单例 `QSPurchase.shared`：

```swift
import StoreKit
import QSInAppPurchase

let purchase = QSPurchase.shared
```

`QSPurchase` 初始化后会自动监听交易更新。你可以按需监听会员状态变化：

```swift
purchase.vipAction = { isVip in
    print("当前 VIP 状态：\(isVip)")
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

也可以通过商品 ID 从已缓存的商品列表中获取：

```swift
let product = QSPurchase.shared.getProduct(by: "com.example.vip.monthly")
```

## 发起购买

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

适合在应用启动、进入会员页或需要刷新会员状态时调用：

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

也可以直接读取当前缓存状态：

```swift
let isVip = QSPurchase.shared.isVip
```

## 取消续订 / 取消试用回调

如果需要监听用户取消自动续订或取消免费试用：

```swift
QSPurchase.shared.cancelAutoRenewAction = { productId, transactionId in
    print("用户取消续订：\(productId), \(transactionId)")
}

QSPurchase.shared.cancelFreeTrialAction = { productId, transactionId in
    print("用户取消试用：\(productId), \(transactionId)")
}
```

如果你的服务端处理失败，可以调用以下方法回滚本地记录，方便下次继续触发处理：

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
- 购买成功后，库会将有效期保存到本地，并通过 `vipAction` 回调刷新 `isVip` 状态。

## License

QSInAppPurchase is available under the MIT license. See the LICENSE file for more info.
