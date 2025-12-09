//
//  SKProduct+Ex.swift
//  QSInAppPurchase
//
//  Created by MacM2 on 12/6/25.
//

import StoreKit

public extension Product {
    // MARK: - Func
    /// 自定义价格格式化
    private func customFormatPrice(price: Decimal) -> String? {
        let locale = priceFormatStyle.locale
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        
        let formattedPrice = formatter.string(from: price as NSNumber)
        return formattedPrice
    }
    
    // MARK: - Property
    // 订阅类型
    var paymentMode: Product.SubscriptionOffer.PaymentMode? {
        return subscription?.introductoryOffer?.paymentMode
    }
    
    /// 试用周期值
    var trialPeriodValue: Int? {
        if let period = subscription?.introductoryOffer?.period {
            if period.unit == .day {
                if period.value % 7 == 0 {
                    return period.value / 7
                }
            }
            return period.value
        }
        return nil
    }
    
    /// 试用周期单位
    var trialPeriodUnit: Product.SubscriptionPeriod.Unit? {
        if let period = subscription?.introductoryOffer?.period {
            if period.unit == .day {
                if period.value % 7 == 0 {
                    return .week
                }
            }
            return period.unit
        }
        return nil
    }
    
    /// 订阅周期值
    var subscriptionPeriodValue: Int? {
        if let period = subscription?.subscriptionPeriod {
            if period.unit == .day {
                if period.value % 7 == 0 {
                    return period.value / 7
                }
            }
            return period.value
        }
        return nil
    }
    
    /// 订阅周期单位
    var subscriptionPeriodUnit: Product.SubscriptionPeriod.Unit? {
        if let period = subscription?.subscriptionPeriod {
            if period.unit == .day {
                if period.value % 7 == 0 {
                    return .week
                }
            }
            return period.unit
        }
        return nil
    }
    
    /// 价格
    var currencyPrice: String? {
        return customFormatPrice(price: price)
    }
    
    /// 折扣价
    var discountCurrencyPrice: String? {
        if let price = subscription?.introductoryOffer?.price {
            return customFormatPrice(price: price)
        }
        return nil
    }
    
    /// 折扣率
    var discountRate: Int? {
        // 折扣类型
        if subscription?.introductoryOffer?.paymentMode == .payAsYouGo {
            let introductoryOffer = subscription?.introductoryOffer
            guard let discountPrice = introductoryOffer?.price.doubleValue else { return nil }
            
            let originalPrice = price.doubleValue
            // 计算折扣百分比
            let discountPercentage = ((originalPrice - discountPrice) / originalPrice) * 100.0
            
            return Int(floor(discountPercentage))
        }
        return nil
    }
    
    /// 每周平均价格
    var weekAveragePrice: String? {
        if subscription?.subscriptionPeriod.unit == .year {
            let weekPrice = price / 52.0
            let formattedPrice = customFormatPrice(price: weekPrice) ?? String.init(format: "%.2f", weekPrice.doubleValue)
            return formattedPrice
        } else if subscription?.subscriptionPeriod.unit == .month {
            let weekPrice = price / 4.0
            let formattedPrice = customFormatPrice(price: weekPrice) ?? String.init(format: "%.2f", weekPrice.doubleValue)
            return formattedPrice
        } else if subscription?.subscriptionPeriod.unit == .day {
            let days = subscription?.subscriptionPeriod.value ?? 1
            let weekPrice = price.doubleValue / Double(days) * 7.0
            let formattedPrice = customFormatPrice(price: Decimal(weekPrice)) ?? String.init(format: "%.2f", weekPrice)
            return formattedPrice
        }
        return currencyPrice
    }
}

public extension Decimal {
    var doubleValue: Double {
        return NSDecimalNumber(decimal: self).doubleValue
    }
}
