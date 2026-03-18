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
    var reportedBy:   [String]

    init(
        id:           String  = UUID().uuidString,
        userId:       String,
        displayName:  String,
        photoURL:     String? = nil,
        text:         String,
        prayingCount: Int     = 0,
        commentCount: Int     = 0,
        createdAt:    Date    = Date(),
        reportedBy:   [String] = []
    ) {
        self.id           = id
        self.userId       = userId
        self.displayName  = displayName
        self.photoURL     = photoURL
        self.text         = text
        self.prayingCount = prayingCount
        self.commentCount = commentCount
        self.createdAt    = createdAt
        self.reportedBy   = reportedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        userId       = try c.decode(String.self, forKey: .userId)
        displayName  = try c.decode(String.self, forKey: .displayName)
        photoURL     = try c.decodeIfPresent(String.self, forKey: .photoURL)
        text         = try c.decode(String.self, forKey: .text)
        prayingCount = try c.decode(Int.self, forKey: .prayingCount)
        commentCount = try c.decode(Int.self, forKey: .commentCount)
        createdAt    = try c.decode(Date.self, forKey: .createdAt)
        reportedBy   = try c.decodeIfPresent([String].self, forKey: .reportedBy) ?? []
    }
}
