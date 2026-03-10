//
//  AdminManager.swift
//  ScriptureScribe
//
//  Centralized admin check. Admins can delete/edit any user's posts and comments,
//  and always have full premium access.
//
//  HOW TO ADD YOUR FIREBASE USER IDS:
//  1. Sign into the app on your phone
//  2. Open Firebase Console → Authentication → Users
//  3. Find your email and copy the "User UID" string
//  4. Paste it into the adminUserIDs set below
//

import Foundation

enum AdminManager {

    /// Firebase UIDs of admin users (Stephanie & Derrick).
    /// Replace these placeholder strings with your real Firebase UIDs.
    private static let adminUserIDs: Set<String> = [
        "AOn9jFrQ3MMfEc9dS0FTijltQ1c2",
        "lW6huU9v3uXlfvWZLMHONVMxDsy1"
    ]

    /// Returns true if the given user ID belongs to an admin.
    static func isAdmin(_ userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return adminUserIDs.contains(userId)
    }
}
