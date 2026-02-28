//
//  DailyAnswer.swift
//  ScriptureScribe
//
//  One user's answer to the Daily Question in the Community tab.
//  Answers are grouped by date so only today's answers appear.
//
//  Firestore path: dailyAnswers/{id}
//  Filtered by:    date == today's date string (e.g. "2026-02-22")
//

import Foundation

struct DailyAnswer: Codable, Identifiable {
    var id:           String
    var userId:       String
    var displayName:  String
    var photoURL:     String?
    var text:         String
    var date:         String   // "YYYY-MM-DD" — today's date string, used for filtering
    var devotionDay:  Int      // 1–30, matches the DailyContent.json day index
    var likeCount:    Int
    var commentCount: Int
    var createdAt:    Date

    init(
        id:           String  = UUID().uuidString,
        userId:       String,
        displayName:  String,
        photoURL:     String? = nil,
        text:         String,
        date:         String,
        devotionDay:  Int,
        likeCount:    Int     = 0,
        commentCount: Int     = 0,
        createdAt:    Date    = Date()
    ) {
        self.id           = id
        self.userId       = userId
        self.displayName  = displayName
        self.photoURL     = photoURL
        self.text         = text
        self.date         = date
        self.devotionDay  = devotionDay
        self.likeCount    = likeCount
        self.commentCount = commentCount
        self.createdAt    = createdAt
    }
}
