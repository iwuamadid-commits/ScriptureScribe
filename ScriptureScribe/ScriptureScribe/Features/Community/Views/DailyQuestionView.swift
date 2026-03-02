//
//  DailyQuestionView.swift
//  ScriptureScribe
//
//  The Daily Question section inside the Community tab.
//  Week strip at top: swipe to browse previous days' questions + answers.
//  "Share your answer" is only available for today — past days are read-only.
//

import SwiftUI

struct DailyQuestionView: View {

    @EnvironmentObject var authVM:       AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager

    @ObservedObject var vm: DailyQuestionViewModel
    var isPremium: Bool = true
    var onUpgrade: (() -> Void)? = nil

    @State private var showCreateAnswer = false
    @State private var showAuth         = false
    @State private var showCalendar     = false
    @State private var selectedAnswer:  DailyAnswer? = nil
    @State private var editingAnswer:   DailyAnswer? = nil

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading…")
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                // Week strip lives OUTSIDE the ScrollView so swipe gestures aren't eaten
                VStack(spacing: 0) {

                    // ── Fixed header: week strip + date label ──────────────
                    VStack(spacing: 0) {
                        WeekStripView(
                            selectedDate: vm.selectedDate,
                            onSelectDate: { date in
                                vm.load(userId: authVM.currentUserID, date: date)
                            }
                        )

                        // "View Calendar" link — right-aligned below the week strip
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

                        Divider()
                        Text(dateLabel(vm.selectedDate).uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(themeManager.currentTheme.primary)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(themeManager.currentTheme.surface)

                    // ── Scrollable content ─────────────────────────────────
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

                            // ── Section intro ────────────────────────────
                            VStack(alignment: .center, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .font(.title3)
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                    Text(vm.isToday ? "Daily Question" : "Past Question")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                }
                                Text(vm.isToday
                                     ? "A new question tied to today's devotion. Share your answer and see how others are hearing from God."
                                     : "Browse past questions and the answers the community shared.")
                                    .font(.subheadline)
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)

                            // ── Question card ─────────────────────────────
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 6) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                        .font(.subheadline)
                                    Text(vm.isToday ? "Today's Question" : "That Day's Question")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                }
                                if let question = vm.questions.first {
                                    Text(question)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(themeManager.currentTheme.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(themeManager.currentTheme.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(themeManager.currentTheme.primary.opacity(0.2), lineWidth: 1)
                            )

                            // ── Share answer (today only, premium only) ──
                            if vm.isToday {
                                Button {
                                    guard isPremium else { onUpgrade?(); return }
                                    if authVM.isSignedIn { showCreateAnswer = true }
                                    else                 { showAuth = true }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "square.and.pencil")
                                        Text("Share your answer")
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .foregroundStyle(themeManager.currentTheme.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(themeManager.currentTheme.primary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }

                            // ── Answers ───────────────────────────────────
                            if vm.answers.isEmpty {
                                Text(vm.isToday
                                     ? "No answers yet. Be the first!"
                                     : "No answers were shared for this day.")
                                    .font(.subheadline)
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(Array(vm.answers.enumerated()), id: \.element.id) { index, answer in
                                        DailyAnswerCardView(
                                            answer:        answer,
                                            currentUserId: authVM.currentUserID,
                                            isLiked:       vm.likedAnswerIds.contains(answer.id),
                                            onLike: {
                                                if let uid = authVM.currentUserID {
                                                    Task { await vm.toggleLike(answer: answer, userId: uid) }
                                                } else {
                                                    showAuth = true
                                                }
                                            },
                                            onEdit:    { editingAnswer = answer },
                                            onComment: { selectedAnswer = answer },
                                            onDelete:  { Task { await vm.deleteAnswer(answer) } }
                                        )
                                        .blur(radius: (!isPremium && index > 0) ? 6 : 0)
                                        .allowsHitTesting(isPremium || index == 0)
                                        .transition(.opacity)
                                    }
                                }

                                if !isPremium && vm.answers.count > 1 {
                                    premiumUpgradeBanner
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }           // closes ScrollView
                }           // closes outer VStack (fixed header + scroll)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $showCreateAnswer) {
                    if let user = authVM.currentUser {
                        CreateAnswerView(
                            question:    vm.question,
                            currentUser: user
                        ) { text in
                            Task {
                                await vm.createAnswer(
                                    userId:      user.id,
                                    displayName: user.displayName,
                                    photoURL:    user.photoURL,
                                    text:        text
                                )
                            }
                        }
                    }
                }
                .sheet(isPresented: $showAuth) {
                    AuthView()
                }
                .sheet(item: $selectedAnswer) { answer in
                    DailyAnswerCommentsView(answer: answer, currentUser: authVM.currentUser)
                }
                .sheet(item: $editingAnswer) { answer in
                    EditTextSheet(title: "Edit Answer", originalText: answer.text) { newText in
                        Task { await vm.editAnswer(answer, newText: newText) }
                    }
                }
                .sheet(isPresented: $showCalendar) {
                    CalendarSheetView(selectedDate: vm.selectedDate) { date in
                        vm.load(userId: authVM.currentUserID, date: date)
                    }
                }
            }
        }
        .onAppear    { vm.load(userId: authVM.currentUserID) }
        .onDisappear { vm.stopListening() }
    }

    // MARK: - Helpers

    private func dateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        let f        = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    // MARK: - Premium Upgrade Banner

    private var premiumUpgradeBanner: some View {
        VStack(spacing: 12) {
            Text("Unlock Full Community")
                .font(.headline)
                .foregroundStyle(themeManager.currentTheme.text)
            Text("See all posts, comment, like, and share your own.")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button { onUpgrade?() } label: {
                HStack(spacing: 8) {
                    ProBadge()
                    Text("Upgrade to Pro")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.80, blue: 0.22),
                                 Color(red: 0.97, green: 0.58, blue: 0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(themeManager.currentTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(themeManager.currentTheme.border.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}
