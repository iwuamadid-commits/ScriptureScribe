//
//  HabitDetailView.swift
//  ScriptureScribe
//
//  Single habit detail — calendar grid, streaks, completion rate, and edit/delete.
//

import SwiftUI

struct HabitDetailView: View {

    @EnvironmentObject var habitsVM:     HabitsViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authVM:       AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let habit: Habit

    @State private var displayedMonth = Date()
    @State private var showEditSheet  = false
    @State private var showDeleteAlert = false

    private var color: Color { Color(hex: habit.colorHex) }

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2   // Monday
        return cal
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // Header card
                    headerCard

                    // Streak & stats row
                    statsRow

                    // Calendar
                    calendarSection

                    // Delete
                    deleteButton
                }
                .padding(16)
            }
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .navigationTitle(habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditSheet = true } label: {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(themeManager.currentTheme.primary)
                    }
                    .accessibilityLabel("Edit habit")
                }
            }
            .sheet(isPresented: $showEditSheet) {
                CreateHabitView(editing: habit)
            }
            .alert("Delete Habit?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    habitsVM.deleteHabit(id: habit.id, userId: authVM.currentUserID)
                    dismiss()
                }
            } message: {
                Text("This will permanently remove \"\(habit.name)\" and all its completion history.")
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 16) {
            Text(habit.emoji)
                .font(.system(size: 44))
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.currentTheme.text)

                if !habit.description.isEmpty {
                    Text(habit.description)
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text("\(habit.goalValue) \(habit.goalUnit) / \(habit.goalPeriod)")
                        .font(.caption)
                        .foregroundStyle(color)
                    Text("\u{2022}")
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                    Text(habit.category)
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.12), lineWidth: 1)
                )
        )
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        let yr = calendar.component(.year, from: displayedMonth)
        let mo = calendar.component(.month, from: displayedMonth)
        let rate = habitsVM.completionRate(year: yr, month: mo)

        return HStack(spacing: 0) {
            statTile(
                value: "\(habitsVM.currentStreak(for: habit))",
                label: "Current Streak",
                icon: "flame.fill",
                iconColor: .orange
            )
            statTile(
                value: "\(habitsVM.bestStreak(for: habit))",
                label: "Best Streak",
                icon: "trophy.fill",
                iconColor: .yellow
            )
            statTile(
                value: "\(Int(rate * 100))%",
                label: "This Month",
                icon: "chart.pie.fill",
                iconColor: color
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.currentTheme.surface.opacity(0.6))
        )
    }

    private func statTile(value: String, label: String, icon: String, iconColor: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(themeManager.currentTheme.text)
            Text(label)
                .font(.caption2)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    // MARK: - Calendar Section

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

            // Calendar grid
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

    /// Returns an array of optional Dates for the calendar grid.
    /// nil entries represent blank cells before the first day.
    private func calendarDays() -> [Date?] {
        let yr = calendar.component(.year, from: displayedMonth)
        let mo = calendar.component(.month, from: displayedMonth)

        guard let firstOfMonth = calendar.date(from: DateComponents(year: yr, month: mo, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        // Weekday of first day (ISO: 1=Mon..7=Sun)
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let isoFirst = firstWeekday == 1 ? 7 : firstWeekday - 1
        let blanks = isoFirst - 1

        var cells: [Date?] = Array(repeating: nil, count: blanks)
        for day in range {
            cells.append(calendar.date(from: DateComponents(year: yr, month: mo, day: day)))
        }
        return cells
    }

    @ViewBuilder
    private func calendarCell(_ date: Date?) -> some View {
        if let date {
            let day = calendar.component(.day, from: date)
            let today = calendar.startOfDay(for: Date())
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isFuture = date > today
            let completed = !isFuture && habitsVM.isCompletedOnDate(habit, date: date)

            ZStack {
                if completed {
                    Circle()
                        .fill(color)
                        .frame(width: 32, height: 32)
                } else if isToday {
                    Circle()
                        .stroke(color, lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                }

                Text("\(day)")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(
                        completed ? .white :
                        isFuture ? themeManager.currentTheme.textSecondary.opacity(0.4) :
                        themeManager.currentTheme.text
                    )
            }
            .frame(height: 36)
        } else {
            Color.clear.frame(height: 36)
        }
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Habit")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}
