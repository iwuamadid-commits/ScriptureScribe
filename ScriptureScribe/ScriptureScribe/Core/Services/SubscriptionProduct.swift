//
//  SubscriptionProduct.swift
//  ScriptureScribe
//
//  Defines the App Store product identifiers for the four subscription tiers.
//

import Foundation

enum SubscriptionProduct: String, CaseIterable {
    case weekly   = "com.scripturescribe.premium.weekly"
    case monthly  = "com.scripturescribe.premium.monthly"
    case yearly   = "com.scripturescribe.premium.yearly"
    case lifetime = "com.scripturescribe.premium.lifetime"

    static var allProductIds: [String] {
        allCases.map(\.rawValue)
    }

    var displayName: String {
        switch self {
        case .weekly:   return "Weekly"
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        case .lifetime: return "Lifetime"
        }
    }
}
