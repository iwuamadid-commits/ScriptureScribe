//
//  AppUser.swift
//  ScriptureScribe
//
//  Represents a registered user of the app.
//  Stored in Firestore at: users/{uid}
//

import Foundation

struct AppUser: Codable, Identifiable {
    var id:          String   // Firebase UID
    var displayName: String
    var email:       String
    var createdAt:   Date
    var photoURL:    String?  // nil until the user sets or syncs a photo
}
