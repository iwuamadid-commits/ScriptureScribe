//
//  Post.swift
//  ScriptureScribe
//
//  A community reflection shared by a user.
//  Stored in Firestore at: posts/{postId}
//
//  verseRef and verseText are empty strings when no verse was attached.
//

import Foundation

struct Post: Codable, Identifiable {
    var id:           String
    var userId:       String
    var displayName:  String   // stored alongside the post so the feed works without extra lookups
    var photoURL:     String?  // author's profile photo at time of posting
    var text:         String
    var verseRef:     String   // e.g. "John 3:16" — empty when none
    var verseText:    String   // the verse text — empty when none
    var createdAt:    Date
    var commentCount: Int
    var likeCount:    Int
    var reportedBy:   [String]

    init(
        id:           String = UUID().uuidString,
        userId:       String,
        displayName:  String,
        photoURL:     String? = nil,
        text:         String,
        verseRef:     String = "",
        verseText:    String = "",
        createdAt:    Date = Date(),
        commentCount: Int = 0,
        likeCount:    Int = 0,
        reportedBy:   [String] = []
    ) {
        self.id           = id
        self.userId       = userId
        self.displayName  = displayName
        self.photoURL     = photoURL
        self.text         = text
        self.verseRef     = verseRef
        self.verseText    = verseText
        self.createdAt    = createdAt
        self.commentCount = commentCount
        self.likeCount    = likeCount
        self.reportedBy   = reportedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        userId       = try c.decode(String.self, forKey: .userId)
        displayName  = try c.decode(String.self, forKey: .displayName)
        photoURL     = try c.decodeIfPresent(String.self, forKey: .photoURL)
        text         = try c.decode(String.self, forKey: .text)
        verseRef     = try c.decode(String.self, forKey: .verseRef)
        verseText    = try c.decode(String.self, forKey: .verseText)
        createdAt    = try c.decode(Date.self, forKey: .createdAt)
        commentCount = try c.decode(Int.self, forKey: .commentCount)
        likeCount    = try c.decode(Int.self, forKey: .likeCount)
        reportedBy   = try c.decodeIfPresent([String].self, forKey: .reportedBy) ?? []
    }
}
