//
//  HabitStatsView.swift
//  ScriptureScribe
//
//  Overall habit stats — monthly calendar, completion ring, streaks,
//  perfect days, totals, and "Done Today" list.
//

import SwiftUI

struct HabitStatsView: View {

    @EnvironmentObject var habitsVM:     HabitsViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var displayedMonth = Date()

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    private var yr: Int { calendar.component(.year, from: displayedMonth) }
    private var mo: Int { calendar.component(.month, from: displayedMonth) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // Completion ring
                    completionRing

                    // Quick stats grid
                    statsGrid

                    // Monthly calendar
                    calendarSection

                    // Done today
                    doneTodaySection
                }
                .padding(16)
            }
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Completion Ring

    private var completionRing: some View {
        let rate = habitsVM.completionRate(year: yr, month: mo)
        let pct  = Int(rate * 100)

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(
                        themeManager.currentTheme.primary.opacity(0.12),
                        lineWidth: 14
                    )
                Circle()
                    .trim(from: 0, to: rate)
                    .stroke(
                        themeManager.currentTheme.primary,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(pct)%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.currentTheme.text)
                    Text("Completed")
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
            }
            .frame(width: 160, height: 160)

            Text(monthYearLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        let totalDone = habitsVM.totalHabitsDone
        let dailyAvg: Double = daysInMonth > 0 ? Double(totalDone) / Double(daysInMonth) : 0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(
                icon: "trophy.fill",
                iconColor: .yellow,
                value: "\(habitsVM.overallBestStreak)",
                label: "Best Streak"
            )
            statCard(
                icon: "star.fill",
                iconColor: .orange,
                value: "\(habitsVM.perfectDays(year: yr, month: mo))",
                label: "Perfect Days"
            )
            statCard(
                icon: "checkmark.circle.fill",
                iconColor: themeManager.currentTheme.primary,
                value: "\(totalDone)",
                label: "Habits Done"
            )
            statCard(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .cyan,
                value: String(format: "%.1f", dailyAvg),
                label: "Daily Average"
            )
        }
    }

    private func statCard(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(themeManager.currentTheme.text)
            Text(label)
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.currentTheme.surface.opacity(0.6))
        )
    }

    // MARK: - Monthly Calendar

    private var calendarSection: some View {
        VStack(spacing: 12) {

            // Month navigation
            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYearLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.currentTheme.text)

                Spacer()

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
                .buttonStyle(.plain)
            }

            // Day-of-week header
            let dayLabels = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(dayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Days
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(calendarDays(), id: \.self) { item in
                    calendarCell(item)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.currentTheme.surface.opacity(0.6))
        )
    }

    @ViewBuilder
    private func calendarCell(_ date: Date?) -> some View {
        if let date {
            let day = calendar.component(.day, from: date)
            let today = calendar.startOfDay(for: Date())
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isFuture = date > today

            // Check if ALL due habits were completed on this date
            let perfect = !isFuture && isPerfectDay(date)
            // Check if at least one habit was completed
            let partial = !isFuture && !perfect && hasAnyCompletion(date)

            ZStack {
                if perfect {
                    Circle()
                        .fill(themeManager.currentTheme.primary)
                        .frame(width: 32, height: 32)
                } else if partial {
                    Circle()
                        .fill(themeManager.currentTheme.primary.opacity(0.25))
                        .frame(width: 32, height: 32)
                } else if isToday {
                    Circle()
                        .stroke(themeManager.currentTheme.primary, lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                }

                Text("\(day)")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(
                        perfect ? .white :
                        isFuture ? themeManager.currentTheme.textSecondary.opacity(0.4) :
                        themeManager.currentTheme.text
                    )
            }
            .frame(height: 36)
        } else {
            Color.clear.frame(height: 36)
        }
    }

    private func isPerfectDay(_ date: Date) -> Bool {
        let wd = isoWeekday(for: date)
        let dueHabits = habitsVM.habits.filter { h in
            h.taskDays.contains(wd) &&
            date >= calendar.startOfDay(for: h.startDate) &&
            (h.endDate == nil || date <= calendar.startOfDay(for: h.endDate!))
        }
        return !dueHabits.isEmpty && dueHabits.allSatisfy { habitsVM.isCompletedOnDate($0, date: date) }
    }

    private func hasAnyCompletion(_ date: Date) -> Bool {
        let ds = habitsVM.dateString(for: date)
        return habitsVM.logs.contains { $0.date == ds }
    }

    // MARK: - Done Today

    private var doneTodaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Done Today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.text)

            let todayLogs = habitsVM.logsCompletedToday
            if todayLogs.isEmpty {
                Text("No habits completed today yet.")
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(todayLogs) { log in
                    if let habit = habitsVM.habits.first(where: { $0.id == log.habitId }) {
                        HStack(spacing: 12) {
                            Text(habit.emoji)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(themeManager.currentTheme.text)
                                Text(timeLabel(log.completedAt))
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(hex: habit.colorHex))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.currentTheme.surface.opacity(0.6))
        )
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    // MARK: - Helpers

    private var monthYearLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    private func moveMonth(by value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func isoWeekday(for date: Date) -> Int {
        let wd = calendar.component(.weekday, from: date)
        return wd == 1 ? 7 : wd - 1
    }

    private func calendarDays() -> [Date?] {
        guard let firstOfMonth = calendar.date(from: DateComponents(year: yr, month: mo, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let isoFirst = firstWeekday == 1 ? 7 : firstWeekday - 1
        let blanks = isoFirst - 1

        var cells: [Date?] = Array(repeating: nil, count: blanks)
        for day in range {
            cells.append(calendar.date(from: DateComponents(year: yr, month: mo, day: day)))
        }
        return cells
    }
}
