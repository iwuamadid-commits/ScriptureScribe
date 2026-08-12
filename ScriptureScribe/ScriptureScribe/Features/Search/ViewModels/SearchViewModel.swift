//
//  SearchViewModel.swift
//  ScriptureScribe
//
//  Manages all state for the three-mode Search tab:
//    • Text   — free-text query sent to API.Bible
//    • Topics — tap a preset topic (Faith, Love, Hope…) to find related verses
//    • Handwriting — Apple Pencil OCR → recognized word → Bible search
//
//  Translation sync: reads @AppStorage("lastBibleId"), which the Reader tab writes
//  every time the user changes translations. No explicit cross-tab wiring required.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class SearchViewModel: ObservableObject {

    // MARK: - Search Mode

    enum SearchMode: String, CaseIterable {
        case text        = "Text"
        case topics      = "Topics"
        case handwriting = "Handwriting"
    }

    // MARK: - Published State

    @Published var searchMode:     SearchMode   = .text
    @Published var query:          String       = ""
    @Published var results:        [SearchResult] = []
    @Published var isLoading:      Bool         = false
    @Published var errorMessage:   String?      = nil
    @Published var selectedTopic:  BibleTopic?  = nil

    // Recent searches — persisted across launches
    @Published private(set) var recentSearches: [String] =
        UserDefaults.standard.stringArray(forKey: "recentBibleSearches") ?? []

    // Handwriting index search (GoodNotes-style OCR index)
    @Published var hwQuery:   String          = ""
    @Published var hwResults: [HandwritingMatch] = []
    @Published private(set) var hwRecentSearches: [String] =
        UserDefaults.standard.stringArray(forKey: "recentHwSearches") ?? []

    // Legacy handwriting OCR state (draw-to-search canvas controls)
    @Published var recognizedText:   String = ""
    @Published var showOCRConfirm:   Bool   = false
    @Published var clearCanvas:      Bool   = false   // set to true → canvas clears itself
    @Published var triggerRecognize: Bool   = false   // set to true → canvas runs OCR

    // MARK: - Topics

    let topics: [BibleTopic] = BibleTopics.all

    // MARK: - Translation Sync
    // Reads the same UserDefaults key that ReaderViewModel writes ("lastBibleId").
    // When the user picks a translation in the Reader, the Search tab automatically
    // searches that same translation next time.

    @AppStorage("lastBibleId") private var lastBibleId: String = ""

    // MARK: - Go-To Reference Suggestions

    /// Book or chapter suggestions shown above search results when the query
    /// looks like a Bible reference (e.g. "Psa" → Psalms, "Psalm 23" → Psalm 23).
    struct GoToSuggestion: Identifiable {
        let id = UUID()
        let label:     String   // Display text, e.g. "Psalms" or "Psalm 23"
        let chapterId: String?  // API chapter ID if available, e.g. "PSA.23"
        let bookApiId: String   // API book ID, e.g. "PSA"
        let verseNum:  String?  // Verse number if present, e.g. "16"
    }

    @Published var goToSuggestions: [GoToSuggestion] = []

    /// Checks if the current query looks like a Bible reference and populates suggestions.
    func updateGoToSuggestions() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { goToSuggestions = []; return }

        // First check: does the full input parse as a "Book Chapter" or "Book Chapter:Verse"?
        if let chapId = BibleReferenceParser.chapterId(from: trimmed) {
            let rawVerse = BibleReferenceParser.verseNumber(from: trimmed)
            let verseNum = (rawVerse?.isEmpty == false) ? rawVerse : nil
            // Build a clean label: "Luke 17" or "Luke 17:5" (strip trailing colon if no verse)
            let label = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            goToSuggestions = [GoToSuggestion(
                label: label,
                chapterId: chapId,
                bookApiId: String(chapId.components(separatedBy: ".").first ?? ""),
                verseNum: verseNum
            )]
            return
        }

        // Second check: partial book name match (e.g. "Psa" → Psalms, "Jo" → Job, Joel, John, etc.)
        let bookMatches = BibleReferenceParser.bookSuggestions(for: trimmed)
        if !bookMatches.isEmpty {
            goToSuggestions = bookMatches.prefix(5).map { match in
                GoToSuggestion(
                    label: match.name,
                    chapterId: "\(match.apiId).1",
                    bookApiId: match.apiId,
                    verseNum: nil
                )
            }
            return
        }

        goToSuggestions = []
    }

    private let api = BibleAPIService()
    private var searchTask: Task<Void, Never>?

    // MARK: - Text Search

    /// Called on every keystroke — waits 400 ms after the user stops typing, then searches.
    func liveSearch() {
        // Update "Go to" suggestions immediately (no debounce needed — it's local)
        updateGoToSuggestions()

        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            results      = []
            errorMessage = nil
            return
        }

        // If the query matches a book name or Bible reference, the "Go to" suggestions
        // handle navigation. Skip the API text search to avoid decoding errors from
        // partial queries like "Psa", "Luke 1", or "John 3:".
        if !goToSuggestions.isEmpty || q.hasSuffix(":") {
            results      = []
            errorMessage = nil
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await search(saveToRecents: false)   // live typing — don't save partial words
        }
    }

    /// Pass saveToRecents: true only when the user explicitly hits the Search key.
    func search(saveToRecents: Bool = true) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard !lastBibleId.isEmpty else {
            errorMessage = "Open the Reader tab first to choose a Bible translation, then come back to search."
            return
        }

        isLoading    = true
        errorMessage = nil
        results      = []

        do {
            results = try await api.search(bibleId: lastBibleId, query: trimmed)
            if saveToRecents && !results.isEmpty { addRecentSearch(trimmed) }
        } catch let err as APIError {
            errorMessage = err.errorDescription ?? err.userMessage
        } catch is CancellationError {
            // Task was cancelled (e.g. user navigated away) — not a real error
        } catch {
            errorMessage = error.userMessage
        }

        isLoading = false
    }

    // MARK: - Topic Search

    func searchTopic(_ topic: BibleTopic) async {
        selectedTopic = topic
        query         = topic.keyword

        guard !lastBibleId.isEmpty else {
            errorMessage = "Open the Reader tab first to choose a Bible translation, then come back to search."
            return
        }

        isLoading    = true
        errorMessage = nil
        results      = []

        do {
            results = try await api.search(bibleId: lastBibleId, query: topic.keyword)
            if !results.isEmpty { addRecentSearch(topic.keyword) }
        } catch let err as APIError {
            errorMessage = err.errorDescription ?? err.userMessage
        } catch is CancellationError {
            // Task was cancelled — not a real error
        } catch {
            errorMessage = error.userMessage
        }

        isLoading = false
    }

    // MARK: - Handwriting OCR

    /// Called by HandwritingCanvasView after Vision finishes recognizing text.
    func handleOCRResult(_ text: String) {
        triggerRecognize = false
        if text.isEmpty {
            errorMessage   = "Couldn't read the handwriting. Try writing larger and more clearly."
            showOCRConfirm = false
        } else {
            recognizedText = text
            showOCRConfirm = true
            errorMessage   = nil
        }
    }

    /// User confirmed the recognized word — run it through Bible search.
    func searchFromRecognizedText() async {
        query          = recognizedText
        showOCRConfirm = false
        clearCanvas    = true   // clear the drawing after search starts
        await search()
    }

    func cancelOCR() {
        recognizedText = ""
        showOCRConfirm = false
    }

    // MARK: - Handwriting Index Search

    /// Searches the per-chapter OCR index built by AnnotationCanvasView.
    /// Synchronous — no network call needed; results come from local UserDefaults.
    /// Pass saveToRecents: true only when the user explicitly hits the Search key.
    func searchHandwriting(saveToRecents: Bool = false) {
        let q = hwQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        hwResults = q.isEmpty ? [] : HandwritingIndexService.shared.search(query: q)
        if saveToRecents && !hwResults.isEmpty && q.count >= 2 { addHwRecentSearch(q) }
    }

    // MARK: - Recent Searches

    func addRecentSearch(_ query: String) {
        var updated = recentSearches
        updated.removeAll { $0.lowercased() == query.lowercased() }
        updated.insert(query, at: 0)
        recentSearches = Array(updated.prefix(10))
        UserDefaults.standard.set(recentSearches, forKey: "recentBibleSearches")
    }

    func removeRecentSearch(_ query: String) {
        recentSearches.removeAll { $0.lowercased() == query.lowercased() }
        UserDefaults.standard.set(recentSearches, forKey: "recentBibleSearches")
    }

    func clearAllRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "recentBibleSearches")
    }

    private func addHwRecentSearch(_ query: String) {
        var updated = hwRecentSearches
        updated.removeAll { $0.lowercased() == query.lowercased() }
        updated.insert(query, at: 0)
        hwRecentSearches = Array(updated.prefix(10))
        UserDefaults.standard.set(hwRecentSearches, forKey: "recentHwSearches")
    }

    func removeHwRecentSearch(_ query: String) {
        hwRecentSearches.removeAll { $0.lowercased() == query.lowercased() }
        UserDefaults.standard.set(hwRecentSearches, forKey: "recentHwSearches")
    }

    func clearAllHwRecentSearches() {
        hwRecentSearches = []
        UserDefaults.standard.removeObject(forKey: "recentHwSearches")
    }

    // MARK: - Utilities

    func clearResults() {
        results         = []
        errorMessage    = nil
        selectedTopic   = nil
        recognizedText  = ""
        showOCRConfirm  = false
        hwResults       = []
        hwQuery         = ""
        goToSuggestions = []
    }
}
