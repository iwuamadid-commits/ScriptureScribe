//
//  CalendarSheetView.swift
//  ScriptureScribe
//
//  Full-month calendar presented as a sheet from the Daily tab.
//  Past days and today are tappable — future days are grayed out.
//  Chevrons navigate months (forward only up to the current month).
//  Tapping a day calls onSelectDate and dismisses the sheet.
//

import SwiftUI

struct CalendarSheetView: View {

    let selectedDate: Date
    let onSelectDate: (Date) -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var displayMonth: Date  // first day of the currently-shown month

    private let calendar    = Calendar.current
    private let dayLetters  = ["M", "T", "W", "T", "F", "S", "S"]
    private let columns     = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    init(selectedDate: Date, onSelectDate: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.onSelectDate = onSelectDate
        // Open on the month that contains selectedDate
        let cal  = Calendar.current
        let comp = cal.dateComponents([.year, .month], from: selectedDate)
        _displayMonth = State(initialValue: cal.date(from: comp) ?? selectedDate)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Month navigation header ────────────────────────────
                monthHeader
                    .padding(.top, 8)

                // ── Day-of-week labels ─────────────────────────────────
                HStack(spacing: 0) {
                    ForEach(Array(dayLetters.enumerated()), id: \.offset) { _, letter in
                        Text(letter)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                // ── Day grid ───────────────────────────────────────────
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(daysInGrid, id: \.offset) { item in
                        if let day = item.date {
                            CalendarDayCell(
                                date:       day,
                                isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                                isToday:    calendar.isDateInToday(day),
                                isFuture:   day > Date(),
                                theme:      themeManager.currentTheme
                            )
                            .onTapGesture {
                                guard day <= Date() else { return }
                                onSelectDate(day)
                                dismiss()
                            }
                        } else {
                            Color.clear.frame(height: 48)
                        }
                    }
                }
                .padding(.horizontal, 8)

                Spacer()
            }
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // "Today" snaps the display back to the current month
                    Button("Today") {
                        if let first = firstOfMonth(for: Date()) {
                            displayMonth = first
                        }
                    }
                    .foregroundStyle(themeManager.currentTheme.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
        }
    }

    // MARK: - Month Header (prev / title / next)

    private var monthHeader: some View {
        HStack(spacing: 0) {

            Button {
                if let prev = calendar.date(byAdding: .month, value: -1, to: displayMonth) {
                    displayMonth = prev
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .frame(width: 48, height: 44)
            }

            Text(monthTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.text)
                .frame(maxWidth: .infinity)

            Button {
                guard canGoForward else { return }
                if let next = calendar.date(byAdding: .month, value: 1, to: displayMonth) {
                    displayMonth = next
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        canGoForward
                            ? themeManager.currentTheme.primary
                            : themeManager.currentTheme.textSecondary.opacity(0.3)
                    )
                    .frame(width: 48, height: 44)
            }
            .disabled(!canGoForward)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Computed Helpers

    /// Whether the forward chevron should be enabled (next month <= current month).
    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: displayMonth),
              let firstOfNext  = firstOfMonth(for: next),
              let firstOfToday = firstOfMonth(for: Date())
        else { return false }
        return firstOfNext <= firstOfToday
    }

    /// Returns the first day of the month containing the given date.
    private func firstOfMonth(for date: Date) -> Date? {
        let comp = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comp)
    }

    private var monthTitle: String {
        let f        = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayMonth)
    }

    /// Grid items: leading nil padding so the first day of the month falls on the right weekday.
    /// Monday = column 0 (ISO week, matching WeekStripView).
    private var daysInGrid: [(offset: Int, date: Date?)] {
        guard
            let range    = calendar.range(of: .day, in: .month, for: displayMonth),
            let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstDay)  // 1=Sun … 7=Sat
        let leadingNils  = (firstWeekday + 5) % 7  // Mon=0, Tue=1 … Sun=6

        var items: [Date?] = Array(repeating: nil, count: leadingNils)
        for offset in range {
            if let date = calendar.date(byAdding: .day, value: offset - 1, to: firstDay) {
                items.append(date)
            }
        }
        return items.enumerated().map { ($0.offset, $0.element) }
    }
}

// MARK: - Day Cell

private struct CalendarDayCell: View {

    let date:       Date
    let isSelected: Bool
    let isToday:    Bool
    let isFuture:   Bool
    let theme:      any AppTheme

    private var dayNumber: String {
        let f        = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? theme.primary : Color.clear)
                .frame(width: 38, height: 38)

            if !isSelected && isToday {
                Circle()
                    .stroke(theme.primary, lineWidth: 1.5)
                    .frame(width: 38, height: 38)
            }

            Text(dayNumber)
                .font(.callout.weight(isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : isFuture
                            ? theme.textSecondary.opacity(0.3)
                            : theme.text
                )
        }
        .frame(height: 48)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}
