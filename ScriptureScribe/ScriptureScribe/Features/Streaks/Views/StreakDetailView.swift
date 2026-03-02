//
//  StreakDetailView.swift
//  ScriptureScribe
//
//  Sheet presented when the user taps the 🔥 streak chip in the nav bar.
//  Shows:
//    • Hero — large flame + day count + motivational subtitle
//    • 35-day calendar grid — filled circle = day app was opened
//    • Stats row — current streak vs. longest streak
//    • Milestone progress bar — next milestone to reach
//

import SwiftUI

struct StreakDetailView: View {

    @EnvironmentObject var streakVM: StreakViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Milestone ladder
    private let milestones = [7, 14, 30, 60, 100, 365]

    private var streak: Int { max(streakVM.currentStreak, 1) }

    private var nextMilestone: Int {
        milestones.first { $0 > streak } ?? milestones.last!
    }

    private var previousMilestone: Int {
        milestones.last { $0 <= streak } ?? 0
    }

    private var milestoneProgress: Double {
        let range = nextMilestone - previousMilestone
        guard range > 0 else { return 1 }
        return Double(streak - previousMilestone) / Double(range)
    }

    private var motivationalSubtitle: String {
        switch streak {
        case 1:        return "Every great streak starts with Day 1."
        case 2...6:    return "You're building momentum. Keep going!"
        case 7...13:   return "One week strong. You're on fire!"
        case 14...29:  return "Two weeks in. Your habit is forming."
        case 30...59:  return "A full month! You're truly committed."
        case 60...99:  return "Two months of faithfulness. Incredible."
        case 100...364: return "100+ days. You're an inspiration."
        default:       return "A full year! Absolutely extraordinary."
        }
    }

    // MARK: - Calendar data (last 35 days: 5 weeks of 7)
    private var calendarDays: [CalendarDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Show last 35 days (5 weeks), starting from the Monday that includes day-34-ago
        // so columns align to weekdays
        var days: [CalendarDay] = []
        for offset in stride(from: -34, through: 0, by: 1) {
            if let date = calendar.date(byAdding: .day, value: offset, to: today) {
                let key = formatter.string(from: date)
                days.append(CalendarDay(date: date, opened: streakVM.openedDates.contains(key)))
            }
        }
        return days
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // ── Hero ──────────────────────────────────────────────
                    VStack(spacing: 6) {
                        Text("🔥")
                            .font(.system(size: 64))
                        Text("\(streak) \(streak == 1 ? "Day" : "Days")")
                            .font(.title.bold())
                        Text(motivationalSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 8)

                    // ── 35-day calendar grid ──────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last 5 Weeks")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                            spacing: 6
                        ) {
                            // Day-of-week header
                            ForEach(["S","M","T","W","T","F","S"], id: \.self) { label in
                                Text(label)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                            // Day cells
                            ForEach(calendarDays) { day in
                                DayCell(day: day)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // ── Stats row ─────────────────────────────────────────
                    HStack(spacing: 0) {
                        statCell(label: "Current", value: "\(streak)")
                        Divider().frame(height: 40)
                        statCell(label: "Best", value: "\(max(streakVM.longestStreak, streak))")
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // ── Milestone progress ────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Next Milestone: \(nextMilestone) days")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(height: 8)
                                Capsule()
                                    .fill(Color.orange)
                                    .frame(width: geo.size.width * milestoneProgress, height: 8)
                            }
                        }
                        .frame(height: 8)
                        .padding(.horizontal, 20)

                        Text("\(nextMilestone - streak) day\(nextMilestone - streak == 1 ? "" : "s") to go")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 24)
                }
            }
            .navigationTitle("Your Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.orange)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Supporting Types

private struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date
    let opened: Bool
}

private struct DayCell: View {

    let day: CalendarDay

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    day.opened
                        ? (isToday ? Color.orange : Color.orange.opacity(0.35))
                        : Color(.systemFill)
                )
            if isToday && !day.opened {
                Circle()
                    .strokeBorder(Color.orange, lineWidth: 1.5)
            }
        }
        .frame(height: 34)
    }
}
