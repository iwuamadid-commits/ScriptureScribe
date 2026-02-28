//
//  PrayerRequest.swift
//  ScriptureScribe
//
//  A prayer request posted in the Community tab.
//  Other users can tap 🙏 (tracked per-user) and leave comments.
//
//  Firestore path:     prayerRequests/{id}
//  Comments sub-path:  prayerRequests/{id}/comments/{commentId}
//  Praying sub-path:   prayerRequests/{id}/prayingUsers/{userId}
//

import Foundation

struct PrayerRequest: Codable, Identifiable {
    var id:           String
    var userId:       String
    var displayName:  String
    var photoURL:     String?
    var text:         String
    var prayingCount: Int     // total users who tapped 🙏
    var commentCount: Int
    var createdAt:    Date

    init(
        id:           String  = UUID().uuidString,
        userId:       String,
        displayName:  String,
        photoURL:     String? = nil,
        text:         String,
        prayingCount: Int     = 0,
        commentCount: Int     = 0,
        createdAt:    Date    = Date()
    ) {
        self.id           = id
        self.userId       = userId
        self.displayName  = displayName
        self.photoURL     = photoURL
        self.text         = text
        self.prayingCount = prayingCount
        self.commentCount = commentCount
        self.createdAt    = createdAt
    }
}
