//
//  PremiumLimits.swift
//  ScriptureScribe
//
//  Central configuration for free-tier limits.
//  Premium users bypass all of these.
//

import Foundation

enum PremiumLimits {

    /// The 4 bookmark color hex values available on the free plan.
    /// (Gold, Red, Green, Blue — out of 8 total)
    static let freeBookmarkColors: Set<String> = [
        "F5C842",  // Gold
        "E84040",  // Red
        "5C8A6B",  // Green
        "4A7EC8",  // Blue
    ]

    /// Maximum bookmark collections (groups) on the free plan.
    static let maxFreeCollections = 2

    /// Maximum habits on the free plan.
    static let maxFreeHabits = 3

    /// Bible version IDs available on the free plan.
    /// KJV (de4e12af7f28f599-02) + one additional free translation.
    static let freeBibleIds: Set<String> = [
        "de4e12af7f28f599-02",  // KJV
        "9879dbb7cfe39e4d-04",  // ASV (American Standard Version — public domain)
    ]

    /// Maximum number of Bible versions on the free plan.
    static let maxFreeBibleVersions = 2
}
