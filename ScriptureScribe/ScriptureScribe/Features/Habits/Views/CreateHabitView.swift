//
//  CreateHabitView.swift
//  ScriptureScribe
//
//  Form for creating or editing a habit.
//  Matches the Habit Tracker reference app's creation flow.
//

import SwiftUI

struct CreateHabitView: View {

    @EnvironmentObject var habitsVM:     HabitsViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authVM:       AuthViewModel
    @Environment(\.dismiss) private var dismiss

    /// If set, we're editing an existing habit.
    var editing: Habit?

    @State private var name         = ""
    @State private var description  = ""
    @State private var emoji        = "\u{2B50}"
    @State private var colorHex     = "4CAF50"
    @State private var category     = "Spiritual"
    @State private var habitType    = "build"
    @State private var goalValue    = 1
    @State private var goalUnit     = "count"
    @State private var goalPeriod   = "daily"
    @State private var taskDays     = Set([1, 2, 3, 4, 5, 6, 7])
    @State private var timeRange    = "anytime"
    @State private var hasEndDate   = false
    @State private var startDate    = Date()
    @State private var endDate      = Date()

    private let colorOptions = [
        "4CAF50", "FF9800", "E91E63", "2196F3", "673AB7",
        "00BCD4", "795548", "9C27B0", "FFC107", "8BC34A",
        "03A9F4", "FF5722"
    ]
    private let emojiOptions = [
        "\u{2B50}", "\u{1F64F}", "\u{1F319}", "\u{1F4D6}", "\u{1F4DA}",
        "\u{271D}\u{FE0F}", "\u{1F4DD}", "\u{1F3B5}", "\u{1F9E0}", "\u{1F4A7}",
        "\u{1F6B6}", "\u{1F64C}", "\u{1F9D8}", "\u{1F3CB}\u{FE0F}", "\u{2764}\u{FE0F}",
        "\u{1F31F}", "\u{1F525}", "\u{1F343}", "\u{2600}\u{FE0F}", "\u{1F30D}"
    ]
    @State private var unitCategory = "Quantity"

    private let categories    = ["Spiritual", "Health", "Life"]
    private let quantityUnits = ["count", "steps", "m", "km", "mile", "ml", "oz", "Cal", "g", "mg", "drink", "chapters", "books"]
    private let timeUnits     = ["sec", "min", "hr"]
    private let dayNames      = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let timeRanges = ["anytime", "morning", "afternoon", "evening"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Emoji + Name
                    nameSection

                    // Color picker
                    colorSection

                    // Category
                    categorySection

                    // Habit Type
                    habitTypeSection

                    // Goal
                    goalSection

                    // Task Days
                    taskDaysSection

                    // Time Range
                    timeRangeSection

                    // Dates
                    dateSection

                    // Save
                    saveButton
                }
                .padding(16)
            }
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .navigationTitle(editing != nil ? "Edit Habit" : "New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { loadEditing() }
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(spacing: 12) {
            // Emoji picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(emojiOptions, id: \.self) { e in
                        Button {
                            emoji = e
                        } label: {
                            Text(e)
                                .font(.title2)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(emoji == e
                                              ? themeManager.currentTheme.primary.opacity(0.2)
                                              : themeManager.currentTheme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(emoji == e
                                                ? themeManager.currentTheme.primary
                                                : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("Habit name", text: $name)
                .font(.headline)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(themeManager.currentTheme.surface))

            TextField("Description (Optional)", text: $description)
                .font(.subheadline)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(themeManager.currentTheme.surface))
        }
        .sectionCard()
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.text)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                ForEach(colorOptions, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: colorHex == hex ? 3 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: hex).opacity(0.6), lineWidth: colorHex == hex ? 1 : 0)
                                    .padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sectionCard()
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.text)
            HStack(spacing: 0) {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        category = cat
                    } label: {
                        Text(cat)
                            .font(.subheadline.weight(category == cat ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                category == cat
                                    ? themeManager.currentTheme.primary
                                    : themeManager.currentTheme.surface
                            )
                            .foregroundStyle(category == cat ? .white : themeManager.currentTheme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .sectionCard()
    }

    private var habitTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Habit Type")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.text)
            HStack(spacing: 0) {
                ForEach(["build", "quit"], id: \.self) { type in
                    Button {
                        habitType = type
                    } label: {
                        Text(type.capitalized)
                            .font(.subheadline.weight(habitType == type ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                habitType == type
                                    ? themeManager.currentTheme.primary
                                    : themeManager.currentTheme.surface
                            )
                            .foregroundStyle(habitType == type ? .white : themeManager.currentTheme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .sectionCard()
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Goal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.text)

            // Goal Period
            HStack(spacing: 0) {
                ForEach(["daily", "weekly", "monthly"], id: \.self) { period in
                    Button {
                        goalPeriod = period
                    } label: {
                        Text(period == "daily" ? "Day-Long" : period == "weekly" ? "Weekly" : "Monthly")
                            .font(.subheadline.weight(goalPeriod == period ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                goalPeriod == period
                                    ? themeManager.currentTheme.primary
                                    : themeManager.currentTheme.surface
                            )
                            .foregroundStyle(goalPeriod == period ? .white : themeManager.currentTheme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Goal Value
            HStack(spacing: 12) {
                Text("Goal Value")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentTheme.text)
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        if goalValue > 1 { goalValue -= 1 }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(themeManager.currentTheme.primary)
                    }
                    .buttonStyle(.plain)

                    Text("\(goalValue)")
                        .font(.headline)
                        .frame(minWidth: 30)
                        .foregroundStyle(themeManager.currentTheme.text)

                    Button {
                        goalValue += 1
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(themeManager.currentTheme.primary)
                    }
                    .buttonStyle(.plain)

                    Text(goalUnit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.currentTheme.primary)

                    Text("/ \(goalPeriod == "daily" ? "Day" : goalPeriod == "weekly" ? "Week" : "Month")")
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
            }

            // Unit Category Picker (Quantity / Time)
            HStack(spacing: 0) {
                ForEach(["Quantity", "Time"], id: \.self) { cat in
                    Button {
                        unitCategory = cat
                        goalUnit = cat == "Quantity" ? quantityUnits[0] : timeUnits[0]
                    } label: {
                        Text(cat)
                            .font(.subheadline.weight(unitCategory == cat ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                unitCategory == cat
                                    ? themeManager.currentTheme.primary
                                    : themeManager.currentTheme.surface
                            )
                            .foregroundStyle(unitCategory == cat ? .white : themeManager.currentTheme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Unit Grid
            let activeUnits = unitCategory == "Quantity" ? quantityUnits : timeUnits
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(activeUnits, id: \.self) { unit in
                    Button {
                        goalUnit = unit
                    } label: {
                        Text(unit)
                            .font(.caption.weight(goalUnit == unit ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(goalUnit == unit
                                          ? themeManager.currentTheme.primary
                                          : themeManager.currentTheme.surface)
                            )
                            .foregroundStyle(goalUnit == unit ? .white : themeManager.currentTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sectionCard()
    }

    private var taskDaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Task Days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.currentTheme.text)
                Spacer()
                Button {
                    if taskDays.count == 7 {
                        taskDays = Set([1, 2, 3, 4, 5])  // weekdays
                    } else {
                        taskDays = Set([1, 2, 3, 4, 5, 6, 7])
                    }
                } label: {
                    Text(taskDays.count == 7 ? "Every Day" : "\(taskDays.count) days")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }

            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let selected = taskDays.contains(day)
                    Button {
                        if selected { taskDays.remove(day) } else { taskDays.insert(day) }
                    } label: {
                        Text(dayNames[day - 1])
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selected
                                          ? themeManager.currentTheme.primary
                                          : themeManager.currentTheme.surface)
                            )
                            .foregroundStyle(selected ? .white : themeManager.currentTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sectionCard()
    }

    private var timeRangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time Range")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.text)
            HStack(spacing: 8) {
                ForEach(timeRanges, id: \.self) { range in
                    let selected = timeRange == range
                    Button {
                        timeRange = range
                    } label: {
                        Text(range.capitalized)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(selected
                                               ? themeManager.currentTheme.primary
                                               : themeManager.currentTheme.surface)
                            )
                            .foregroundStyle(selected ? .white : themeManager.currentTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sectionCard()
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Habit Term")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.text)

            HStack {
                Text("Start Date")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentTheme.text)
                Spacer()
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .tint(themeManager.currentTheme.primary)
            }

            HStack {
                Text("End Date")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentTheme.text)
                Spacer()
                if hasEndDate {
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                        .tint(themeManager.currentTheme.primary)
                } else {
                    Button("No End") { hasEndDate = true }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(themeManager.currentTheme.primary))
                        .foregroundStyle(.white)
                }
                if hasEndDate {
                    Button {
                        hasEndDate = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sectionCard()
    }

    private var saveButton: some View {
        Button {
            saveHabit()
        } label: {
            Text("Save")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(name.isEmpty
                              ? themeManager.currentTheme.primary.opacity(0.3)
                              : themeManager.currentTheme.primary)
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(name.isEmpty)
    }

    // MARK: - Save

    private func saveHabit() {
        var habit = editing ?? Habit(name: name)
        habit.name        = name.trimmingCharacters(in: .whitespaces)
        habit.description = description
        habit.emoji       = emoji
        habit.colorHex    = colorHex
        habit.category    = category
        habit.habitType   = habitType
        habit.goalValue   = goalValue
        habit.goalUnit    = goalUnit
        habit.goalPeriod  = goalPeriod
        habit.taskDays    = Array(taskDays).sorted()
        habit.timeRange   = timeRange
        habit.startDate   = startDate
        habit.endDate     = hasEndDate ? endDate : nil

        if editing != nil {
            habitsVM.updateHabit(habit, userId: authVM.currentUserID)
        } else {
            habitsVM.addHabit(habit, userId: authVM.currentUserID)
        }
        dismiss()
    }

    private func loadEditing() {
        guard let h = editing else { return }
        name        = h.name
        description = h.description
        emoji       = h.emoji
        colorHex    = h.colorHex
        category    = h.category
        habitType   = h.habitType
        goalValue   = h.goalValue
        goalUnit    = h.goalUnit
        unitCategory = ["sec", "min", "hr"].contains(h.goalUnit) ? "Time" : "Quantity"
        goalPeriod  = h.goalPeriod
        taskDays    = Set(h.taskDays)
        timeRange   = h.timeRange
        startDate   = h.startDate
        hasEndDate  = h.endDate != nil
        endDate     = h.endDate ?? Date()
    }
}

// MARK: - Section Card Modifier

private struct SectionCardModifier: ViewModifier {
    @EnvironmentObject var themeManager: ThemeManager
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(themeManager.currentTheme.surface.opacity(0.6))
            )
    }
}

extension View {
    func sectionCard() -> some View {
        modifier(SectionCardModifier())
    }
}
