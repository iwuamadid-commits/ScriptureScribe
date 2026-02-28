//
//  HabitProgressView.swift
//  ScriptureScribe
//
//  Dedicated habit progress screen with circular ring, +/- counter,
//  timer for time-based habits, and number pad for exact entry.
//

import SwiftUI

struct HabitProgressView: View {

    @EnvironmentObject var habitsVM:     HabitsViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authVM:       AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let habit: Habit

    @State private var showNumberPad  = false
    @State private var showStatDetail = false
    @State private var showEditSheet  = false

    // Timer state (for time-based habits)
    @State private var timerIsRunning  = false
    @State private var elapsedSeconds  = 0
    @State private var timerStartedAt: Date? = nil
    @State private var timer: Timer?   = nil

    private var color: Color { Color(hex: habit.colorHex) }

    private var isDrinkHabit: Bool {
        ["oz", "ml", "drink"].contains(habit.goalUnit)
    }

    private var currentProgress: Int {
        habitsVM.progress(for: habit)
    }

    private var progressFraction: Double {
        min(Double(currentProgress) / Double(max(habit.goalValue, 1)), 1.0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Habit identity
                        habitHeader

                        // Progress visual (cup for drinks, ring for others)
                        progressVisual

                        // Controls
                        if habit.isTimeBasedUnit {
                            timerControls
                        } else {
                            counterControls
                        }
                    }
                    .padding(24)
                }

                Spacer()

                // Bottom tabs
                bottomTabs
            }
            .background(color.opacity(0.04).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        stopTimer()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(themeManager.currentTheme.text)
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text(habit.emoji)
                        Text(habit.name)
                            .font(.headline)
                            .foregroundStyle(themeManager.currentTheme.text)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEditSheet = true } label: {
                            Label("Edit Habit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            habitsVM.deleteHabit(id: habit.id, userId: authVM.currentUserID)
                            dismiss()
                        } label: {
                            Label("Delete Habit", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(themeManager.currentTheme.text)
                    }
                }
            }
            .toolbarBackground(color.opacity(0.04), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showNumberPad) {
                NumberPadSheet(unit: habit.goalUnit, color: color) { amount in
                    habitsVM.logCompletion(habitId: habit.id, value: amount, userId: authVM.currentUserID)
                }
            }
            .sheet(isPresented: $showStatDetail) {
                HabitDetailView(habit: habit)
            }
            .sheet(isPresented: $showEditSheet) {
                CreateHabitView(editing: habit)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                if let start = timerStartedAt, timerIsRunning {
                    elapsedSeconds = Int(Date().timeIntervalSince(start))
                }
            }
            .onDisappear { stopTimer() }
        }
    }

    // MARK: - Habit Header

    private var habitHeader: some View {
        VStack(spacing: 4) {
            Text(habit.emoji)
                .font(.system(size: 48))
            if currentProgress >= habit.goalValue {
                Text("Goal reached!")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Progress Visual

    @ViewBuilder
    private var progressVisual: some View {
        if isDrinkHabit {
            cupView
        } else {
            progressRing
        }
    }

    private var progressRing: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(color.opacity(0.12), lineWidth: 16)

            // Progress arc
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    currentProgress >= habit.goalValue ? Color.green : color,
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: currentProgress)

            // Center content
            if habit.isTimeBasedUnit {
                timerDisplay
            } else {
                counterDisplay
            }
        }
        .frame(width: 220, height: 220)
    }

    // MARK: - Cup View (Drink Habits)

    private var cupView: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                // Cup outline
                CupShape()
                    .stroke(color.opacity(0.25), lineWidth: 2.5)
                    .frame(width: 140, height: 180)

                // Water fill
                CupShape()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.6), color.opacity(0.35)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 140, height: 180)
                    .mask(alignment: .bottom) {
                        Rectangle()
                            .frame(height: 180 * progressFraction)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .animation(.easeInOut(duration: 0.3), value: currentProgress)

                // Cup outline on top (so it draws over the fill)
                CupShape()
                    .stroke(color.opacity(0.4), lineWidth: 2.5)
                    .frame(width: 140, height: 180)
            }
            .frame(width: 140, height: 180)

            // Counter below cup
            counterDisplay
        }
    }

    // MARK: - Counter Display & Controls

    private var counterDisplay: some View {
        VStack(spacing: 2) {
            HStack(spacing: 12) {
                Button {
                    habitsVM.removeLastLog(habitId: habit.id, userId: authVM.currentUserID)
                } label: {
                    Image(systemName: "minus")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(currentProgress > 0 ? themeManager.currentTheme.textSecondary : themeManager.currentTheme.textSecondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(currentProgress <= 0)

                Text("\(currentProgress)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.currentTheme.text)

                Button {
                    habitsVM.logCompletion(habitId: habit.id, userId: authVM.currentUserID)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Text("/\(habit.goalValue) \(habit.goalUnit)")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
    }

    private var counterControls: some View {
        HStack(spacing: 20) {
            // Undo button
            Button {
                habitsVM.removeLastLog(habitId: habit.id, userId: authVM.currentUserID)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle().fill(themeManager.currentTheme.surface)
                    )
                    .foregroundStyle(currentProgress > 0 ? themeManager.currentTheme.textSecondary : themeManager.currentTheme.textSecondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(currentProgress <= 0)

            // Add exact amount button
            Button {
                showNumberPad = true
            } label: {
                Text("Add")
                    .font(.headline)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(color)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            // Quick complete
            Button {
                let remaining = habit.goalValue - currentProgress
                if remaining > 0 {
                    habitsVM.logCompletion(habitId: habit.id, value: remaining, userId: authVM.currentUserID)
                }
            } label: {
                Image(systemName: currentProgress >= habit.goalValue ? "checkmark.circle.fill" : "checkmark")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle().fill(currentProgress >= habit.goalValue ? Color.green.opacity(0.15) : themeManager.currentTheme.surface)
                    )
                    .foregroundStyle(currentProgress >= habit.goalValue ? .green : themeManager.currentTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Timer Display & Controls

    private var timerDisplay: some View {
        VStack(spacing: 4) {
            Text(formattedElapsed)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(themeManager.currentTheme.text)

            Text("/\(habit.goalValue) \(habit.goalUnit)")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
    }

    private var timerControls: some View {
        VStack(spacing: 20) {
            // Play / Pause
            Button {
                if timerIsRunning {
                    pauseTimer()
                } else {
                    startTimer()
                }
            } label: {
                Image(systemName: timerIsRunning ? "pause.fill" : "play.fill")
                    .font(.title)
                    .frame(width: 72, height: 48)
                    .background(
                        Capsule().fill(color)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            // Save time + number pad
            HStack(spacing: 16) {
                // Save elapsed time
                Button {
                    let valueInUnit = convertSecondsToGoalUnit(elapsedSeconds)
                    if valueInUnit > 0 {
                        habitsVM.logCompletion(habitId: habit.id, value: valueInUnit, userId: authVM.currentUserID)
                    }
                    elapsedSeconds = 0
                    timerStartedAt = nil
                    stopTimer()
                } label: {
                    Text("Save Time")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(elapsedSeconds > 0 ? color : color.opacity(0.3))
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(elapsedSeconds == 0)

                // Manual entry
                Button {
                    showNumberPad = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Timer Logic

    private func startTimer() {
        timerIsRunning = true
        timerStartedAt = Date().addingTimeInterval(TimeInterval(-elapsedSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if let start = timerStartedAt {
                    elapsedSeconds = Int(Date().timeIntervalSince(start))
                }
            }
        }
    }

    private func pauseTimer() {
        timerIsRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func stopTimer() {
        pauseTimer()
    }

    private func convertSecondsToGoalUnit(_ seconds: Int) -> Int {
        switch habit.goalUnit {
        case "sec": return seconds
        case "min": return seconds / 60
        case "hr":  return seconds / 3600
        default:    return seconds / 60
        }
    }

    private var formattedElapsed: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Bottom Tabs

    private var bottomTabs: some View {
        Button {
            showStatDetail = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.title3)
                Text("Stat")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
        .background(themeManager.currentTheme.surface)
    }
}

// MARK: - Number Pad Sheet

struct NumberPadSheet: View {

    let unit: String
    let color: Color
    let onAdd: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with Cancel
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 36)
            .padding(.bottom, 8)

            // Display
            Text(value.isEmpty ? "0" : value)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .padding(.bottom, 2)

            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            // Number pad
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(["1", "2", "3",
                         "4", "5", "6",
                         "7", "8", "9",
                         "AC", "0", "DEL"], id: \.self) { key in
                    if key == "AC" {
                        Button {
                            value = ""
                        } label: {
                            Text("AC")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.systemGray5))
                                )
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    } else if key == "DEL" {
                        Button {
                            if !value.isEmpty { value.removeLast() }
                        } label: {
                            Image(systemName: "delete.backward")
                                .font(.body)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.systemGray5))
                                )
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            if value.count < 6 {
                                value += key
                            }
                        } label: {
                            Text(key)
                                .font(.title3.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.systemGray6))
                                )
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)

            // Enter button
            Button {
                if let amount = Int(value), amount > 0 {
                    onAdd(amount)
                }
                dismiss()
            } label: {
                Text("Enter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(value.isEmpty || value == "0" ? color.opacity(0.3) : color)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(value.isEmpty || value == "0")
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Cup Shape

/// A tapered glass/cup shape — wider at the top, narrower at the bottom, with rounded corners.
struct CupShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topInset: CGFloat = rect.width * 0.05   // slight inset at top
        let bottomInset: CGFloat = rect.width * 0.2  // more narrow at bottom
        let cornerRadius: CGFloat = 12

        let topLeft = CGPoint(x: rect.minX + topInset, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX - topInset, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX - bottomInset, y: rect.maxY - cornerRadius)
        let bottomLeft = CGPoint(x: rect.minX + bottomInset, y: rect.maxY - cornerRadius)

        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y))
        path.addQuadCurve(
            to: CGPoint(x: bottomRight.x - cornerRadius, y: rect.maxY),
            control: CGPoint(x: bottomRight.x, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bottomLeft.x + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bottomLeft.x, y: bottomLeft.y),
            control: CGPoint(x: bottomLeft.x, y: rect.maxY)
        )
        path.addLine(to: topLeft)
        path.closeSubpath()
        return path
    }
}
