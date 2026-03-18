//
//  Comment.swift
//  ScriptureScribe
//
//  A reply to a community post.
//  Stored in Firestore at: posts/{postId}/comments/{commentId}
//

import Foundation

struct Comment: Codable, Identifiable {
    var id:              String
    var postId:          String
    var userId:          String
    var displayName:     String
    var photoURL:        String?  // author's profile photo at time of commenting
    var text:            String
    var likeCount:       Int
    var parentCommentId: String?  // nil = top-level; set = reply to another comment
    var createdAt:       Date
    var reportedBy:      [String]

    init(
        id:              String = UUID().uuidString,
        postId:          String,
        userId:          String,
        displayName:     String,
        photoURL:        String? = nil,
        text:            String,
        likeCount:       Int = 0,
        parentCommentId: String? = nil,
        createdAt:       Date = Date(),
        reportedBy:      [String] = []
    ) {
        self.id              = id
        self.postId          = postId
        self.userId          = userId
        self.displayName     = displayName
        self.photoURL        = photoURL
        self.text            = text
        self.likeCount       = likeCount
        self.parentCommentId = parentCommentId
        self.createdAt       = createdAt
        self.reportedBy      = reportedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        postId          = try c.decode(String.self, forKey: .postId)
        userId          = try c.decode(String.self, forKey: .userId)
        displayName     = try c.decode(String.self, forKey: .displayName)
        photoURL        = try c.decodeIfPresent(String.self, forKey: .photoURL)
        text            = try c.decode(String.self, forKey: .text)
        likeCount       = try c.decode(Int.self, forKey: .likeCount)
        parentCommentId = try c.decodeIfPresent(String.self, forKey: .parentCommentId)
        createdAt       = try c.decode(Date.self, forKey: .createdAt)
        reportedBy      = try c.decodeIfPresent([String].self, forKey: .reportedBy) ?? []
    }
}
