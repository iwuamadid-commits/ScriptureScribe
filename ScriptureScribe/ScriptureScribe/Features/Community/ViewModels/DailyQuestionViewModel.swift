//
//  DailyQuestionViewModel.swift
//  ScriptureScribe
//
//  Manages the Daily Question section of the Community tab.
//  - Loads questions from DailyContent.json (same entries as the Daily tab)
//  - Supports any date: swipe the week strip to browse previous days' questions + answers
//  - Real-time Firestore listener for answers filtered to the selected date
//  - Tracks which answers the current user has liked
//

import Combine
import FirebaseFirestore
import Foundation
import SwiftUI

@MainActor
final class DailyQuestionViewModel: ObservableObject {

    @Published var questions:      [String]      = []   // reflection questions for the selected date
    @Published var answers:        [DailyAnswer] = []
    @Published var likedAnswerIds: Set<String>   = []
    @Published var isLoading:      Bool          = false
    @Published var errorMessage:   String?       = nil

    /// The date whose questions + answers are currently displayed.
    @Published var selectedDate:   Date          = Date()

    /// True when the displayed date is today (controls whether "Share answer" appears).
    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    /// Single-string form used by CreateAnswerView (both questions joined).
    var question: String { questions.joined(separator: "\n\n") }

    private let firestore:    FirestoreService = FirestoreService()
    private var listener:     ListenerRegistration?
    private(set) var dateString: String = ""   // "YYYY-MM-DD" for the selected date
    private(set) var devotionDay: Int   = 1

    // MARK: - Load

    /// Call this on appear and whenever the user selects a new date.
    func load(userId: String? = nil, date: Date = Date()) {
        isLoading    = true
        selectedDate = date
        devotionDay  = dayIndex(for: date)
        dateString   = isoDateString(for: date)
        questions    = loadQuestions(for: devotionDay)

        // Clear stale answers and restart the Firestore listener for the new date.
        answers = []
        stopListening()
        startListening(date: dateString)

        isLoading = false

        if let uid = userId {
            Task { await loadLikedIds(userId: uid) }
        }
    }

    // MARK: - Listener

    private func startListening(date: String) {
        listener = firestore.listenToDailyAnswers(date: date) { [weak self] answers in
            self?.answers = answers
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Likes

    private func loadLikedIds(userId: String) async {
        let ids = (try? await firestore.fetchLikedAnswerIds(userId: userId)) ?? []
        likedAnswerIds = Set(ids)
    }

    func toggleLike(answer: DailyAnswer, userId: String) async {
        let alreadyLiked = likedAnswerIds.contains(answer.id)
        if alreadyLiked { likedAnswerIds.remove(answer.id) }
        else             { likedAnswerIds.insert(answer.id) }

        do {
            try await firestore.toggleAnswerLike(
                answerId: answer.id,
                userId:   userId,
                isLiked:  alreadyLiked
            )
        } catch {
            if alreadyLiked { likedAnswerIds.insert(answer.id) }
            else             { likedAnswerIds.remove(answer.id) }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Create Answer

    func createAnswer(
        userId:      String,
        displayName: String,
        photoURL:    String?,
        text:        String
    ) async {
        let answer = DailyAnswer(
            userId:      userId,
            displayName: displayName,
            photoURL:    photoURL,
            text:        text.trimmingCharacters(in: .whitespacesAndNewlines),
            date:        dateString,
            devotionDay: devotionDay
        )
        do {
            try await firestore.createDailyAnswer(answer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Edit Answer

    func editAnswer(_ answer: DailyAnswer, newText: String) async {
        do {
            try await firestore.updateDailyAnswer(id: answer.id, text: newText.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete Answer

    func deleteAnswer(_ answer: DailyAnswer) async {
        withAnimation(.easeOut(duration: 0.35)) {
            answers.removeAll { $0.id == answer.id }
        }
        do {
            try await firestore.deleteDailyAnswer(id: answer.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Returns a 1–30 day index for the given date (same rotation as DailyViewModel).
    private func dayIndex(for date: Date) -> Int {
        let cal       = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) ?? 1
        return ((dayOfYear - 1) % 30) + 1
    }

    /// "YYYY-MM-DD" string for the given date.
    private func isoDateString(for date: Date) -> String {
        let f        = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// Loads the reflection question for the given devotion-day index from DailyContent.json —
    /// the same source used by the Daily tab, so both places always show the same question.
    private func loadQuestions(for day: Int) -> [String] {
        guard
            let url     = Bundle.main.url(forResource: "DailyContent", withExtension: "json"),
            let data    = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([DailyEntry].self, from: data),
            let entry   = entries.first(where: { $0.day == day }),
            let first   = entry.reflectionQuestions.first
        else {
            return ["What is God teaching you today?"]
        }
        return [first]
    }
}
