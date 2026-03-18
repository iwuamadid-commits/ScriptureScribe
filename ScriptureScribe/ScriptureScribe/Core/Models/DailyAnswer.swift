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
    var reportedBy:   [String]

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
        createdAt:    Date    = Date(),
        reportedBy:   [String] = []
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
        self.reportedBy   = reportedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        userId       = try c.decode(String.self, forKey: .userId)
        displayName  = try c.decode(String.self, forKey: .displayName)
        photoURL     = try c.decodeIfPresent(String.self, forKey: .photoURL)
        text         = try c.decode(String.self, forKey: .text)
        date         = try c.decode(String.self, forKey: .date)
        devotionDay  = try c.decode(Int.self, forKey: .devotionDay)
        likeCount    = try c.decode(Int.self, forKey: .likeCount)
        commentCount = try c.decode(Int.self, forKey: .commentCount)
        createdAt    = try c.decode(Date.self, forKey: .createdAt)
        reportedBy   = try c.decodeIfPresent([String].self, forKey: .reportedBy) ?? []
    }
}
