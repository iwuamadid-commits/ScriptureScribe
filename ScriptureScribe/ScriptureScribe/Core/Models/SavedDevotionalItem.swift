//
//  SavedDevotionalItem.swift
//  ScriptureScribe
//
//  A prayer or devotional that the user has saved (hearted) from the Daily tab.
//  Stored in Firestore at users/{userId}/savedItems/{id}.
//

import Foundation

struct SavedDevotionalItem: Codable, Identifiable {

    var id: String            = UUID().uuidString

    let userId:        String
    let type:          String  // "prayer" or "devotional"
    let verseReference: String // e.g. "John 3:16"
    let content:       String  // the full prayer or devotional text
    let entryDate:     String  // "YYYY-MM-DD" — the day this content was the daily entry
    let savedAt:       Date
}
