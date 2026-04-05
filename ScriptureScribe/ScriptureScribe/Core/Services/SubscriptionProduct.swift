//
//  SubscriptionProduct.swift
//  ScriptureScribe
//
//  Defines the App Store product identifiers for the four subscription tiers.
//

import Foundation

enum SubscriptionProduct: String, CaseIterable {
    case monthly  = "com.scripturescribe.premium.month"
    case yearly   = "com.scripturescribe.premium.yearly"

    static var allProductIds: [String] {
        allCases.map(\.rawValue)
    }

    var displayName: String {
        switch self {
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        }
    }
}
