//
//  SuggestedHabitsView.swift
//  ScriptureScribe
//
//  Browse and add pre-built spiritual habits, plus activate Bible-in-a-Year.
//

import SwiftUI

struct SuggestedHabitsView: View {

    @EnvironmentObject var habitsVM:     HabitsViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authVM:       AuthViewModel
    @Environment(\.dismiss) private var dismiss

    private var suggested: [Habit] {
        habitsVM.loadSuggestedHabits()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {

                    // Suggested habits
                    ForEach(suggested) { habit in
                        suggestedCard(habit)
                    }
                }
                .padding(16)
            }
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .navigationTitle("Suggested Habits")
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

    // MARK: - Suggested Card

    private func suggestedCard(_ habit: Habit) -> some View {
        let alreadyAdded = habitsVM.habits.contains { $0.name == habit.name }
        let color = Color(hex: habit.colorHex)

        return Button {
            guard !alreadyAdded else { return }
            habitsVM.addHabit(habit, userId: authVM.currentUserID)
        } label: {
            HStack(spacing: 14) {
                Text(habit.emoji)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(color.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.text)
                    HStack(spacing: 4) {
                        Text("\(habit.goalValue) \(habit.goalUnit) / \(habit.goalPeriod)")
                            .font(.caption)
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                        Text("\u{2022}")
                            .font(.caption)
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                        Text(habit.category)
                            .font(.caption)
                            .foregroundStyle(color)
                    }
                }
                Spacer()
                if alreadyAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(color.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
    }
}
