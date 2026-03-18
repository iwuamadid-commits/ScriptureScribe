//
//  GratitudePost.swift
//  ScriptureScribe
//
//  A post in the Gratitude section of the Community tab.
//  Users share what they are grateful for today, with an optional photo.
//
//  Firestore path: gratitudePosts/{id}
//  Storage path:   gratitudePhotos/{id}.jpg
//

import Foundation

struct GratitudePost: Codable, Identifiable {
    var id:          String
    var userId:      String
    var displayName: String
    var photoURL:    String?   // the author's profile photo URL (nil if no profile photo)
    var imageURL:     String?   // legacy: Firebase Storage download URL (nil if text-only)
    var imageBase64:  String?   // inline compressed JPEG stored directly in Firestore
    var text:         String
    var likeCount:    Int
    var commentCount: Int
    var createdAt:    Date
    var reportedBy:   [String]

    init(
        id:           String  = UUID().uuidString,
        userId:       String,
        displayName:  String,
        photoURL:     String? = nil,
        imageURL:     String? = nil,
        imageBase64:  String? = nil,
        text:         String,
        likeCount:    Int     = 0,
        commentCount: Int     = 0,
        createdAt:    Date    = Date(),
        reportedBy:   [String] = []
    ) {
        self.id           = id
        self.userId       = userId
        self.displayName  = displayName
        self.photoURL     = photoURL
        self.imageURL     = imageURL
        self.imageBase64  = imageBase64
        self.text         = text
        self.likeCount    = likeCount
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
        imageURL     = try c.decodeIfPresent(String.self, forKey: .imageURL)
        imageBase64  = try c.decodeIfPresent(String.self, forKey: .imageBase64)
        text         = try c.decode(String.self, forKey: .text)
        likeCount    = try c.decode(Int.self, forKey: .likeCount)
        commentCount = try c.decode(Int.self, forKey: .commentCount)
        createdAt    = try c.decode(Date.self, forKey: .createdAt)
        reportedBy   = try c.decodeIfPresent([String].self, forKey: .reportedBy) ?? []
    }
}
