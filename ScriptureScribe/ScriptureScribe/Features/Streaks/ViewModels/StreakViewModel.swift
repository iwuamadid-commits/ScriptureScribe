//
//  StreakViewModel.swift
//  ScriptureScribe
//
//  Tracks how many days in a row the user has opened the Bible app.
//
//  Rules:
//    • Open the app today → streak stays at today's count (doesn't double-count)
//    • Open the app the day after yesterday → streak increases by 1
//    • Miss a day → streak resets to 1 (starting fresh from today)
//    • The longest streak ever achieved is also recorded
//
//  All data is saved via @AppStorage (UserDefaults) so it survives app restarts.
//  Firebase sync will be added in Phase 6.
//

import Combine
import SwiftUI

@MainActor
final class StreakViewModel: ObservableObject {

    @Published var currentStreak: Int = 0
    @Published var longestStreak: Int = 0

    @AppStorage("streak_currentCount")   private var storedCurrentStreak: Int    = 0
    @AppStorage("streak_longestCount")   private var storedLongestStreak: Int    = 0
    @AppStorage("streak_lastOpenedDate") private var lastOpenedDateString: String = ""

    init() {
        updateStreak()
    }

    // MARK: - Update on App Open

    /// Call this every time the Reader tab appears. It handles all the date math.
    func updateStreak() {
        let calendar  = Calendar.current
        let today     = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat  = "yyyy-MM-dd"
        formatter.locale      = Locale(identifier: "en_US_POSIX")
        let todayString = formatter.string(from: today)

        if lastOpenedDateString == todayString {
            // Already counted today — just sync the published values
            currentStreak = storedCurrentStreak
            longestStreak = storedLongestStreak

        } else if
            let lastDate = formatter.date(from: lastOpenedDateString),
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
            calendar.isDate(lastDate, inSameDayAs: yesterday)
        {
            // Yesterday → extend the streak
            storedCurrentStreak += 1
            currentStreak = storedCurrentStreak

        } else if lastOpenedDateString.isEmpty {
            // Very first time opening the app
            storedCurrentStreak = 1
            currentStreak = 1

        } else {
            // Missed one or more days → start over
            storedCurrentStreak = 1
            currentStreak = 1
        }

        // Update the longest streak record if this is a new high
        if currentStreak > storedLongestStreak {
            storedLongestStreak = currentStreak
            longestStreak = currentStreak
        } else {
            longestStreak = storedLongestStreak
        }

        // Mark today as visited
        lastOpenedDateString = todayString
    }
}
