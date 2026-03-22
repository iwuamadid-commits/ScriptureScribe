//
//  WeekStripView.swift
//  ScriptureScribe
//
//  Horizontal 7-day strip used at the top of the Daily tab and the Community Daily tab.
//
//  • Swipe left  → forward one week (capped at the current week)
//  • Swipe right → back one week (unlimited)
//  • "Today" row appears whenever a past week is shown; tapping it snaps back
//    to the current week and selects today.
//  • Reacts to external selectedDate changes (e.g. CalendarSheetView) by
//    automatically scrolling to that date's week.
//

import SwiftUI

struct WeekStripView: View {

    let selectedDate: Date
    let onSelectDate: (Date) -> Void
    var isPremium: Bool = true
    @EnvironmentObject var themeManager: ThemeManager

    /// How many weeks from the *current* calendar week we are showing.
    /// 0 = this week, -1 = last week, -2 = two weeks ago, etc.
    @State private var weekOffset: Int  = 0
    @State private var stripWidth: CGFloat = 0

    private let calendar   = Calendar.current
    private let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    // MARK: - Computed Week Helpers

    /// Monday of the current real-world calendar week.
    private var baseMonday: Date {
        let today   = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)  // 1=Sun … 7=Sat
        let offset  = (weekday + 5) % 7                          // Mon=0 … Sun=6
        return calendar.date(byAdding: .day, value: -offset, to: today) ?? today
    }

    /// Monday of the week currently on screen.
    private var displayedMonday: Date {
        calendar.date(byAdding: .day, value: weekOffset * 7, to: baseMonday) ?? baseMonday
    }

    /// The seven days of the currently displayed week.
    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: displayedMonday) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── "Today" button — only visible when viewing a past week ──
            if weekOffset != 0 {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            weekOffset = 0
                        }
                        onSelectDate(calendar.startOfDay(for: Date()))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.right")
                                .font(.caption2.weight(.semibold))
                            Text("Today")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(themeManager.currentTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(themeManager.currentTheme.primary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                }
                .padding(.top, 6)
                .padding(.bottom, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Day circles row ──────────────────────────────────────────
            // DayCircles have no tap gesture of their own; taps and swipes are
            // both handled by the single DragGesture below to avoid conflicts.
            HStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { i, day in
                    DayCircle(
                        letter:     dayLetters[i],
                        date:       day,
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                        isToday:    calendar.isDateInToday(day),
                        isFuture:   day > Date(),
                        isLocked:   !isPremium && !calendar.isDateInToday(day),
                        theme:      themeManager.currentTheme
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // ── Unified tap + swipe gesture ──────────────────────────────
            // minimumDistance: 0 so every touch is captured here instead of
            // leaking to child views. onEnded decides: small movement = tap,
            // large horizontal movement = week change.
            .background(
                GeometryReader { g in
                    Color.clear.onAppear { stripWidth = g.size.width }
                }
            )
            // Make the entire rectangular area—including space between circles—touchable.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height

                        if abs(dx) < 12 && abs(dy) < 12 {
                            // Short movement → treat as a tap on whichever day slot
                            guard stripWidth > 0 else { return }
                            let slotWidth = stripWidth / 7
                            let rawIndex  = Int(value.startLocation.x / slotWidth)
                            let index     = min(max(rawIndex, 0), 6)
                            let tappedDay = weekDays[index]
                            guard tappedDay <= Date() else { return }
                            // Free users can only select today
                            if !isPremium && !calendar.isDateInToday(tappedDay) { return }
                            onSelectDate(tappedDay)
                        } else if abs(dx) > 40 && abs(dx) > abs(dy) {
                            // Free users cannot swipe to other weeks
                            guard isPremium else { return }
                            // Clear horizontal swipe → change week
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if dx < 0 {
                                    if weekOffset < 0 { weekOffset += 1 }
                                } else {
                                    weekOffset -= 1
                                }
                            }
                        }
                    }
            )
        }
        // When the parent changes selectedDate (e.g. CalendarSheet or "Try Again"),
        // snap the strip to show the week containing that date.
        .onChange(of: selectedDate) { _, newDate in
            let newOffset = weekOffsetFor(newDate)
            if newOffset != weekOffset {
                withAnimation(.easeInOut(duration: 0.2)) {
                    weekOffset = newOffset
                }
            }
        }
    }

    // MARK: - Helper

    /// Returns the weekOffset value that would display the week containing `date`.
    private func weekOffsetFor(_ date: Date) -> Int {
        let dayStart = calendar.startOfDay(for: date)
        let weekday  = calendar.component(.weekday, from: dayStart)
        let shift    = (weekday + 5) % 7
        let monday   = calendar.date(byAdding: .day, value: -shift, to: dayStart) ?? dayStart
        let daysDiff = calendar.dateComponents([.day], from: baseMonday, to: monday).day ?? 0
        return daysDiff / 7
    }
}

// MARK: - Single Day Circle

private struct DayCircle: View {

    let letter:     String
    let date:       Date
    let isSelected: Bool
    let isToday:    Bool
    let isFuture:   Bool
    var isLocked:   Bool = false
    let theme:      any AppTheme

    private var dayNumber: String {
        let f        = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(letter)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isFuture || isLocked ? theme.textSecondary.opacity(0.4) : theme.textSecondary)

            ZStack {
                Circle()
                    .fill(isSelected ? theme.primary : Color.clear)
                    .frame(width: 34, height: 34)

                if !isSelected && isToday {
                    Circle()
                        .stroke(theme.primary, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }

                if isLocked && !isSelected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary.opacity(0.35))
                } else {
                    Text(dayNumber)
                        .font(.caption.weight(isSelected || isToday ? .semibold : .regular))
                        .foregroundStyle(
                            isSelected
                                ? Color.white
                                : isFuture
                                    ? theme.textSecondary.opacity(0.35)
                                    : theme.text
                        )
                }
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}
