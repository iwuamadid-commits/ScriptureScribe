//
//  HabitLog.swift
//  ScriptureScribe
//
//  Records a single completion of a habit on a given date.
//  Persisted to UserDefaults (offline-first) and synced to Firestore.
//

import Foundation

struct HabitLog: Codable, Identifiable {
    var id: String = UUID().uuidString
    var habitId: String
    var date: String              // "YYYY-MM-DD"
    var value: Int = 1            // amount completed toward goal
    var note: String = ""         // optional memo
    var chapters: [String]? = nil // chapter IDs for Bible reading logs (e.g. ["GEN.1"])
    var completedAt: Date = Date()
}
