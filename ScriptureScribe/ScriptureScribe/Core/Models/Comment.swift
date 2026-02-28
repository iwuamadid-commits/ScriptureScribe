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

    init(
        id:              String = UUID().uuidString,
        postId:          String,
        userId:          String,
        displayName:     String,
        photoURL:        String? = nil,
        text:            String,
        likeCount:       Int = 0,
        parentCommentId: String? = nil,
        createdAt:       Date = Date()
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
    }
}
