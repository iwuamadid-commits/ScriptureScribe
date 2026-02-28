//
//  Habit.swift
//  ScriptureScribe
//
//  A user-created habit to track daily or weekly.
//  Persisted to UserDefaults (offline-first) and synced to Firestore.
//

import Foundation

struct Habit: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var description: String = ""
    var emoji: String = "\u{2B50}"         // ⭐
    var colorHex: String = "4CAF50"
    var category: String = "Spiritual"     // Spiritual, Health, Life
    var habitType: String = "build"        // "build" or "quit"
    var goalValue: Int = 1
    var goalUnit: String = "count"         // "count", "minutes", "chapters"
    var goalPeriod: String = "daily"       // "daily" or "weekly"
    var taskDays: [Int] = [1, 2, 3, 4, 5, 6, 7]  // ISO: 1=Mon..7=Sun
    var timeRange: String = "anytime"      // anytime, morning, afternoon, evening
    var isBibleReadingPlan: Bool = false
    var startDate: Date = Date()
    var endDate: Date? = nil
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    var isTimeBasedUnit: Bool {
        ["sec", "min", "hr"].contains(goalUnit)
    }
}
