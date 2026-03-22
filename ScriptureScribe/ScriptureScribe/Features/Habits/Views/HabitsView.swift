//
//  HabitsView.swift
//  ScriptureScribe
//
//  Main Habits tab — shows today's habits with a week strip,
//  category filter, and color-coded habit cards.
//

import SwiftUI

struct HabitsView: View {

    @EnvironmentObject var habitsVM:       HabitsViewModel
    @EnvironmentObject var themeManager:   ThemeManager
    @EnvironmentObject var authVM:         AuthViewModel
    @EnvironmentObject var appNav:         AppNavigation
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel

    @State private var showCreateHabit   = false
    @State private var showSuggested     = false
    @State private var showStats         = false
    @State private var showCalendar      = false
    @State private var showPaywall       = false
    @State private var selectedHabit:    Habit?
    @State private var draggedHabitID:   String?
    @State private var dragOffset:       CGFloat = 0
    @State private var dragSourceIndex:  Int = 0

    private var atHabitLimit: Bool {
        !subscriptionVM.isPremium && habitsVM.habits.count >= PremiumLimits.maxFreeHabits
    }

    private let categories = ["All", "Spiritual", "Health", "Life"]
    private let habitRowHeight: CGFloat = 84
    private let habitSpacing: CGFloat = 12

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Week strip + View Calendar (matches Daily tab layout)
                VStack(spacing: 0) {
                    WeekStripView(selectedDate: habitsVM.selectedDate) { date in
                        habitsVM.selectedDate = date
                    }

                    HStack {
                        Spacer()
                        Button {
                            showCalendar = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                Text("View Calendar")
                                    .font(.caption.weight(.medium))
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .foregroundStyle(themeManager.currentTheme.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                .background(themeManager.currentTheme.surface)

                // Category filter + habit limit indicator
                HStack {
                    categoryFilter
                    if !subscriptionVM.isPremium {
                        Spacer()
                        Text("\(habitsVM.habits.count)/\(PremiumLimits.maxFreeHabits)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(atHabitLimit
                                             ? .red
                                             : themeManager.currentTheme.textSecondary)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(themeManager.currentTheme.surface)
                .overlay(alignment: .bottom) {
                    Divider()
                }

                // Habit list
                if habitsVM.habits.isEmpty {
                    emptyState
                } else if habitsVM.habitsForSelectedDate.isEmpty {
                    noHabitsForDay
                } else {
                    habitList
                }
            }
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showStats = true } label: {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(themeManager.currentTheme.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            if atHabitLimit { showPaywall = true }
                            else           { showCreateHabit = true }
                        } label: {
                            Label(
                                atHabitLimit ? "Custom Habit (Limit Reached)" : "Custom Habit",
                                systemImage: atHabitLimit ? "lock.fill" : "plus"
                            )
                        }
                        Button {
                            if atHabitLimit { showPaywall = true }
                            else           { showSuggested = true }
                        } label: {
                            Label(
                                atHabitLimit ? "Suggested Habits (Limit Reached)" : "Suggested Habits",
                                systemImage: atHabitLimit ? "lock.fill" : "sparkles"
                            )
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(themeManager.currentTheme.primary)
                            .coachMark("habits-add-button")
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showCreateHabit) {
                CreateHabitView()
            }
            .sheet(isPresented: $showSuggested) {
                SuggestedHabitsView()
            }
            .sheet(isPresented: $showStats) {
                HabitStatsView()
            }
            .sheet(item: $selectedHabit) { habit in
                HabitProgressView(habit: habit)
            }
            .sheet(isPresented: $showCalendar) {
                CalendarSheetView(selectedDate: habitsVM.selectedDate) { date in
                    habitsVM.selectedDate = date
                }
            }
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        HStack(spacing: 8) {
            ForEach(categories, id: \.self) { cat in
                let isSelected = habitsVM.selectedCategory == cat
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        habitsVM.selectedCategory = cat
                    }
                } label: {
                    Text(cat)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected
                                      ? themeManager.currentTheme.primary
                                      : themeManager.currentTheme.surface)
                        )
                        .foregroundStyle(isSelected ? .white : themeManager.currentTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Habit List

    private var habitList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: habitSpacing) {
                ForEach(habitsVM.habitsForSelectedDate) { habit in
                    let isDragged = draggedHabitID == habit.id

                    habitCard(habit)
                        .coachMark("habits-card", active: habit == habitsVM.habitsForSelectedDate.first)
                        // Insertion indicator line
                        .overlay(alignment: .top) {
                            if !isDragged, draggedHabitID != nil,
                               habitShowsTopIndicator(habit) {
                                Capsule()
                                    .fill(themeManager.currentTheme.primary.opacity(0.5))
                                    .frame(height: 3)
                                    .padding(.horizontal, 24)
                                    .offset(y: -3)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if !isDragged, draggedHabitID != nil,
                               habitShowsBottomIndicator(habit) {
                                Capsule()
                                    .fill(themeManager.currentTheme.primary.opacity(0.5))
                                    .frame(height: 3)
                                    .padding(.horizontal, 24)
                                    .offset(y: 3)
                            }
                        }
                        .zIndex(isDragged ? 1 : 0)
                        .offset(y: isDragged
                                ? dragOffset
                                : habitDisplacement(for: habit))
                        .scaleEffect(isDragged ? 1.03 : 1.0)
                        .shadow(
                            color: isDragged ? .black.opacity(0.15) : .clear,
                            radius: 8, x: 0, y: 4
                        )
                        .animation(.spring(response: 0.45, dampingFraction: 0.82),
                                   value: habitDisplacement(for: habit))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8),
                                   value: draggedHabitID)
                        // Long press — scroll-friendly view modifier
                        .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
                            if !pressing, draggedHabitID == habit.id,
                               dragOffset == 0 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    draggedHabitID = nil
                                }
                            }
                        }) {
                            let habits = habitsVM.habitsForSelectedDate
                            dragSourceIndex = habits.firstIndex(where: { $0.id == habit.id }) ?? 0
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                draggedHabitID = habit.id
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        // Drag — inert (minimumDistance 10000) until this card is being dragged
                        .simultaneousGesture(
                            DragGesture(minimumDistance: isDragged ? 0 : 10000)
                                .onChanged { drag in
                                    guard isDragged else { return }
                                    dragOffset = drag.translation.height
                                }
                                .onEnded { _ in
                                    guard draggedHabitID != nil else { return }
                                    let proposed = proposedHabitIndex()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        if proposed != dragSourceIndex {
                                            habitsVM.moveHabits(
                                                from: IndexSet(integer: dragSourceIndex),
                                                to: proposed > dragSourceIndex ? proposed + 1 : proposed,
                                                userId: authVM.currentUserID
                                            )
                                        }
                                        dragOffset = 0
                                        draggedHabitID = nil
                                    }
                                }
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDisabled(draggedHabitID != nil)
    }

    // MARK: - Habit Card

    private func habitCard(_ habit: Habit) -> some View {
        let prog = habitsVM.progress(for: habit)
        let done = habitsVM.isCompleted(habit)
        let color = Color(hex: habit.colorHex)

        return HStack(spacing: 14) {
                // Emoji with checkmark badge when done
                ZStack(alignment: .topTrailing) {
                    Text(habit.emoji)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(color.opacity(done ? 0.3 : 0.12))
                        )
                    if done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .offset(x: 4, y: -4)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.text)
                    Text("\(prog)/\(habit.goalValue) \(habit.goalUnit)")
                        .font(.caption)
                        .foregroundStyle(done ? color : themeManager.currentTheme.textSecondary)
                }

                Spacer()

                // Quick action: checkmark when done, circle/plus when not
                if done {
                    Button {
                        habitsVM.removeLastLog(habitId: habit.id, userId: authVM.currentUserID)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                } else if habit.goalValue == 1 {
                    Button {
                        habitsVM.logCompletion(habitId: habit.id, userId: authVM.currentUserID)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        habitsVM.logCompletion(habitId: habit.id, userId: authVM.currentUserID)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(done ? 0.15 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(color.opacity(done ? 0.3 : 0.12), lineWidth: 1)
                    )
            )
        .contentShape(Rectangle())
        .onTapGesture {
            guard draggedHabitID == nil else { return }
            selectedHabit = habit
        }
    }

    // MARK: - Drag Helpers

    /// Effective slot height: card + spacing between cards.
    private var slotHeight: CGFloat { habitRowHeight + habitSpacing }

    /// Target index based on how far the item has been dragged.
    private func proposedHabitIndex() -> Int {
        let habits = habitsVM.habitsForSelectedDate
        let moveCount = Int(round(dragOffset / slotHeight))
        return min(max(dragSourceIndex + moveCount, 0), habits.count - 1)
    }

    /// Items between source and target shift by one slot height,
    /// opening a clear gap at the insertion point.
    private func habitDisplacement(for habit: Habit) -> CGFloat {
        guard draggedHabitID != nil, habit.id != draggedHabitID else { return 0 }
        let habits = habitsVM.habitsForSelectedDate
        guard let itemIndex = habits.firstIndex(where: { $0.id == habit.id }) else { return 0 }

        let proposed = proposedHabitIndex()

        if dragSourceIndex < proposed {
            // Dragging down — items between source and target shift up
            if itemIndex > dragSourceIndex && itemIndex <= proposed {
                return -slotHeight
            }
        } else if dragSourceIndex > proposed {
            // Dragging up — items between target and source shift down
            if itemIndex >= proposed && itemIndex < dragSourceIndex {
                return slotHeight
            }
        }
        return 0
    }

    /// Whether a habit card should show the accent insertion line at its top edge.
    private func habitShowsTopIndicator(_ habit: Habit) -> Bool {
        guard draggedHabitID != nil else { return false }
        let proposed = proposedHabitIndex()
        guard dragSourceIndex > proposed else { return false }
        let habits = habitsVM.habitsForSelectedDate
        return habits.firstIndex(where: { $0.id == habit.id }) == proposed
    }

    /// Whether a habit card should show the accent insertion line at its bottom edge.
    private func habitShowsBottomIndicator(_ habit: Habit) -> Bool {
        guard draggedHabitID != nil else { return false }
        let proposed = proposedHabitIndex()
        guard dragSourceIndex < proposed else { return false }
        let habits = habitsVM.habitsForSelectedDate
        return habits.firstIndex(where: { $0.id == habit.id }) == proposed
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(themeManager.currentTheme.primary.opacity(0.4))
            Text("No habits yet.\nTap + to create one or browse suggested habits.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .padding(.horizontal, 40)

            Button { showSuggested = true } label: {
                Text("Browse Suggested Habits")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(themeManager.currentTheme.primary))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noHabitsForDay: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 40))
                .foregroundStyle(themeManager.currentTheme.primary.opacity(0.4))
            Text("No habits scheduled for this day.")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Make Habit identifiable for sheet(item:)
extension Habit: Hashable {
    static func == (lhs: Habit, rhs: Habit) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
