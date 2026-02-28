//
//  HabitsViewModel.swift
//  ScriptureScribe
//
//  Manages all habits and completion logs.
//
//  Storage strategy (mirrors BookmarksViewModel):
//  - Always saved to UserDefaults (works offline, no sign-in required).
//  - When signed in, every add/delete is also mirrored to Firestore.
//  - On sign-in, Firestore data is fetched and merged with local data.
//

import Combine
import SwiftUI

@MainActor
final class HabitsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var habits: [Habit] = []
    @Published var logs: [HabitLog] = []
    @Published var selectedDate: Date = Date()
    @Published var selectedCategory: String = "All"

    // MARK: - Private

    private let habitsKey = "scripture_scribe_habits"
    private let logsKey   = "scripture_scribe_habit_logs"
    private let firestore = FirestoreService()

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 2  // Monday
        return cal
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init() {
        loadHabits()
        loadLogs()
    }

    // MARK: - Date Helpers

    var selectedDateString: String {
        dateFormatter.string(from: selectedDate)
    }

    func dateString(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    var isSelectedDateToday: Bool {
        calendar.isDateInToday(selectedDate)
    }

    // MARK: - Filtered Habits

    /// Habits that should appear on the selected date, filtered by taskDays and category.
    var habitsForSelectedDate: [Habit] {
        let weekday = isoWeekday(for: selectedDate)
        return habits
            .filter { $0.taskDays.contains(weekday) }
            .filter { selectedDate >= calendar.startOfDay(for: $0.startDate) }
            .filter { habit in
                if let end = habit.endDate {
                    return selectedDate <= calendar.startOfDay(for: end)
                }
                return true
            }
            .filter { selectedCategory == "All" || $0.category == selectedCategory }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// ISO weekday: 1=Monday..7=Sunday
    private func isoWeekday(for date: Date) -> Int {
        let wd = calendar.component(.weekday, from: date) // 1=Sun..7=Sat
        return wd == 1 ? 7 : wd - 1
    }

    // MARK: - Progress

    func progress(for habit: Habit) -> Int {
        let ds = selectedDateString
        return logs
            .filter { $0.habitId == habit.id && $0.date == ds }
            .reduce(0) { $0 + $1.value }
    }

    func isCompleted(_ habit: Habit) -> Bool {
        progress(for: habit) >= habit.goalValue
    }

    func progressOnDate(for habit: Habit, date: Date) -> Int {
        let ds = dateString(for: date)
        return logs
            .filter { $0.habitId == habit.id && $0.date == ds }
            .reduce(0) { $0 + $1.value }
    }

    func isCompletedOnDate(_ habit: Habit, date: Date) -> Bool {
        progressOnDate(for: habit, date: date) >= habit.goalValue
    }

    // MARK: - Streaks

    func currentStreak(for habit: Habit) -> Int {
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // If today isn't completed yet, start from yesterday
        if !isCompletedOnDate(habit, date: checkDate) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            checkDate = yesterday
        }

        while true {
            let wd = isoWeekday(for: checkDate)
            if habit.taskDays.contains(wd) {
                if isCompletedOnDate(habit, date: checkDate) {
                    streak += 1
                } else {
                    break
                }
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            if prev < calendar.startOfDay(for: habit.startDate) { break }
            checkDate = prev
        }
        return streak
    }

    func bestStreak(for habit: Habit) -> Int {
        var best = 0
        var current = 0
        var checkDate = calendar.startOfDay(for: habit.startDate)
        let today = calendar.startOfDay(for: Date())

        while checkDate <= today {
            let wd = isoWeekday(for: checkDate)
            if habit.taskDays.contains(wd) {
                if isCompletedOnDate(habit, date: checkDate) {
                    current += 1
                    best = max(best, current)
                } else {
                    current = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: checkDate) else { break }
            checkDate = next
        }
        return best
    }

    // MARK: - Overall Stats

    /// Overall completion rate for a given month (0.0 - 1.0).
    func completionRate(year: Int, month: Int) -> Double {
        var totalDue = 0
        var totalDone = 0

        let components = DateComponents(year: year, month: month, day: 1)
        guard let firstDay = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else { return 0 }

        let today = calendar.startOfDay(for: Date())

        for day in range {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  date <= today else { continue }
            let wd = isoWeekday(for: date)
            for habit in habits {
                if habit.taskDays.contains(wd) &&
                   date >= calendar.startOfDay(for: habit.startDate) {
                    if let end = habit.endDate, date > calendar.startOfDay(for: end) { continue }
                    totalDue += 1
                    if isCompletedOnDate(habit, date: date) {
                        totalDone += 1
                    }
                }
            }
        }
        return totalDue == 0 ? 0 : Double(totalDone) / Double(totalDue)
    }

    /// Number of perfect days (all habits completed) in a month.
    func perfectDays(year: Int, month: Int) -> Int {
        let components = DateComponents(year: year, month: month, day: 1)
        guard let firstDay = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else { return 0 }

        let today = calendar.startOfDay(for: Date())
        var count = 0

        for day in range {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  date <= today else { continue }
            let wd = isoWeekday(for: date)
            let dueHabits = habits.filter { h in
                h.taskDays.contains(wd) &&
                date >= calendar.startOfDay(for: h.startDate) &&
                (h.endDate == nil || date <= calendar.startOfDay(for: h.endDate!))
            }
            if !dueHabits.isEmpty && dueHabits.allSatisfy({ isCompletedOnDate($0, date: date) }) {
                count += 1
            }
        }
        return count
    }

    /// Best overall streak (consecutive days where all due habits completed).
    var overallBestStreak: Int {
        guard let earliest = habits.map({ $0.startDate }).min() else { return 0 }
        var best = 0
        var current = 0
        var checkDate = calendar.startOfDay(for: earliest)
        let today = calendar.startOfDay(for: Date())

        while checkDate <= today {
            let wd = isoWeekday(for: checkDate)
            let dueHabits = habits.filter { h in
                h.taskDays.contains(wd) &&
                checkDate >= calendar.startOfDay(for: h.startDate) &&
                (h.endDate == nil || checkDate <= calendar.startOfDay(for: h.endDate!))
            }
            if !dueHabits.isEmpty && dueHabits.allSatisfy({ isCompletedOnDate($0, date: checkDate) }) {
                current += 1
                best = max(best, current)
            } else if !dueHabits.isEmpty {
                current = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: checkDate) else { break }
            checkDate = next
        }
        return best
    }

    /// Total habits completed (all time).
    var totalHabitsDone: Int {
        logs.reduce(0) { $0 + $1.value }
    }

    /// Logs completed today.
    var logsCompletedToday: [HabitLog] {
        let today = dateString(for: Date())
        return logs
            .filter { $0.date == today }
            .sorted { $0.completedAt > $1.completedAt }
    }

    // MARK: - Habit CRUD

    func addHabit(_ habit: Habit, userId: String? = nil) {
        var h = habit
        h.sortOrder = (habits.map(\.sortOrder).max() ?? -1) + 1
        habits.append(h)
        saveHabits()
        if let userId {
            Task { try? await firestore.saveHabit(h, userId: userId) }
        }
    }

    func updateHabit(_ updated: Habit, userId: String? = nil) {
        guard let idx = habits.firstIndex(where: { $0.id == updated.id }) else { return }
        habits[idx] = updated
        saveHabits()
        if let userId {
            Task { try? await firestore.saveHabit(updated, userId: userId) }
        }
    }

    /// Handles drag-to-reorder within the filtered habit list.
    func moveHabits(from source: IndexSet, to destination: Int, userId: String? = nil) {
        var filtered = habitsForSelectedDate
        filtered.move(fromOffsets: source, toOffset: destination)

        // Rebuild full ordering: keep non-filtered habits in place,
        // slot the reordered filtered habits into their original positions.
        let filteredIds = Set(filtered.map(\.id))
        let allSorted = habits.sorted { $0.sortOrder < $1.sortOrder }

        var result: [Habit] = []
        var filteredIndex = 0
        for habit in allSorted {
            if filteredIds.contains(habit.id) {
                result.append(filtered[filteredIndex])
                filteredIndex += 1
            } else {
                result.append(habit)
            }
        }

        // Re-number all habits
        for (index, habit) in result.enumerated() {
            if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
                habits[idx].sortOrder = index
            }
        }

        saveHabits()
        if let userId {
            Task {
                for habit in habits {
                    try? await firestore.saveHabit(habit, userId: userId)
                }
            }
        }
    }

    func deleteHabit(id: String, userId: String? = nil) {
        habits.removeAll { $0.id == id }
        logs.removeAll { $0.habitId == id }
        saveHabits()
        saveLogs()
        if let userId {
            Task {
                try? await firestore.deleteHabit(id: id, userId: userId)
                // Also delete associated logs from Firestore
                let logsToDelete = logs.filter { $0.habitId == id }
                for log in logsToDelete {
                    try? await firestore.deleteHabitLog(id: log.id, userId: userId)
                }
            }
        }
    }

    // MARK: - Log Completion

    func logCompletion(habitId: String, value: Int = 1, note: String = "", chapters: [String]? = nil, userId: String? = nil) {
        let log = HabitLog(
            habitId: habitId,
            date: selectedDateString,
            value: value,
            note: note,
            chapters: chapters,
            completedAt: Date()
        )
        logs.append(log)
        saveLogs()
        if let userId {
            Task { try? await firestore.saveHabitLog(log, userId: userId) }
        }
    }

    /// Removes the most recent log for a habit on the selected date (undo).
    func removeLastLog(habitId: String, userId: String? = nil) {
        let ds = selectedDateString
        if let idx = logs.lastIndex(where: { $0.habitId == habitId && $0.date == ds }) {
            let removed = logs.remove(at: idx)
            saveLogs()
            if let userId {
                Task { try? await firestore.deleteHabitLog(id: removed.id, userId: userId) }
            }
        }
    }

    // MARK: - Suggested Habits

    func loadSuggestedHabits() -> [Habit] {
        guard let url = Bundle.main.url(forResource: "SuggestedHabits", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }

        struct Template: Decodable {
            let name: String
            let description: String
            let emoji: String
            let colorHex: String
            let category: String
            let habitType: String
            let goalValue: Int
            let goalUnit: String
            let goalPeriod: String
            let taskDays: [Int]
            let timeRange: String
        }

        guard let templates = try? JSONDecoder().decode([Template].self, from: data) else { return [] }
        return templates.map { t in
            Habit(
                name: t.name,
                description: t.description,
                emoji: t.emoji,
                colorHex: t.colorHex,
                category: t.category,
                habitType: t.habitType,
                goalValue: t.goalValue,
                goalUnit: t.goalUnit,
                goalPeriod: t.goalPeriod,
                taskDays: t.taskDays,
                timeRange: t.timeRange
            )
        }
    }

    // MARK: - Firestore Sync

    func syncOnSignIn(userId: String) async {
        // Habits
        let cloudHabits = (try? await firestore.fetchHabits(userId: userId)) ?? []
        for local in habits {
            if !cloudHabits.contains(where: { $0.id == local.id }) {
                try? await firestore.saveHabit(local, userId: userId)
            }
        }
        for cloud in cloudHabits {
            if !habits.contains(where: { $0.id == cloud.id }) {
                habits.append(cloud)
            }
        }
        saveHabits()

        // Logs
        let cloudLogs = (try? await firestore.fetchHabitLogs(userId: userId)) ?? []
        for local in logs {
            if !cloudLogs.contains(where: { $0.id == local.id }) {
                try? await firestore.saveHabitLog(local, userId: userId)
            }
        }
        for cloud in cloudLogs {
            if !logs.contains(where: { $0.id == cloud.id }) {
                logs.append(cloud)
            }
        }
        saveLogs()
    }

    // MARK: - Persistence (UserDefaults)

    private func saveHabits() {
        guard let data = try? JSONEncoder().encode(habits) else { return }
        UserDefaults.standard.set(data, forKey: habitsKey)
    }

    private func loadHabits() {
        guard let data = UserDefaults.standard.data(forKey: habitsKey),
              let saved = try? JSONDecoder().decode([Habit].self, from: data) else { return }
        habits = saved
    }

    private func saveLogs() {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        UserDefaults.standard.set(data, forKey: logsKey)
    }

    private func loadLogs() {
        guard let data = UserDefaults.standard.data(forKey: logsKey),
              let saved = try? JSONDecoder().decode([HabitLog].self, from: data) else { return }
        logs = saved
    }
}
