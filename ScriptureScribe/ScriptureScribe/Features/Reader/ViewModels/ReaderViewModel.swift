//
//  ReaderViewModel.swift
//  ScriptureScribe
//
//  The brain of the Bible Reader. It holds everything the reader screen needs to know:
//  which translation/book/chapter is selected, the actual text content, loading states,
//  and the user's reading preferences (font, size, spacing).
//
//  Views just read from this and call its functions — they never touch the API directly.
//

import SwiftUI
import Combine

@MainActor
final class ReaderViewModel: ObservableObject {

    // MARK: - Data

    @Published var translations:    [BibleTranslation]   = []
    @Published var books:           [BibleBook]          = []
    @Published var chapters:        [BibleChapter]       = []
    @Published var chapterContent:  BibleChapterContent?

    // MARK: - Current Selection

    @Published var selectedTranslation: BibleTranslation?
    @Published var selectedBook:        BibleBook?
    @Published var selectedChapter:     BibleChapter?

    // MARK: - UI State

    @Published var isLoadingTranslations = false
    @Published var isLoadingBooks        = false
    @Published var isLoadingContent      = false
    @Published var errorMessage:         String?
    /// Incremented every time chapter content finishes loading, even when the chapter ID
    /// hasn't changed (e.g. navigating to a verse in the already-open chapter).
    /// ReaderView watches this instead of chapterContent?.id so the animation always fires.
    @Published var contentLoadCounter:   Int = 0
    @Published var showTranslationBrowser = false
    @Published var bookSortOrder:        SortOrder = .canonical

    enum SortOrder { case canonical, alphabetical }

    // MARK: - Reading Preferences (persist across app launches)

    @AppStorage("fontSize")       var fontSize:      Double = 18
    @AppStorage("lineSpacing")    var lineSpacing:   Double = 10
    @AppStorage("fontChoice")     var fontChoice:    String = "System"
    @AppStorage("showRedLetters") var showRedLetters: Bool   = true
    @AppStorage("textAlignment")  var textAlignment:  String = "leading"

    // MARK: - Restore Last Position

    @AppStorage("lastBibleId")   private var lastBibleId:   String = ""
    @AppStorage("lastBookId")    private var lastBookId:    String = ""
    @AppStorage("lastChapterId") private var lastChapterId: String = ""

    // MARK: - My Versions (user's saved translations)

    /// Ordered list of translation IDs the user has added. Persisted in UserDefaults.
    @Published var myVersionIds: [String] = UserDefaults.standard.stringArray(forKey: "myVersionIds") ?? []

    /// Resolves IDs to full BibleTranslation objects (in order).
    var myVersions: [BibleTranslation] {
        myVersionIds.compactMap { id in translations.first(where: { $0.id == id }) }
    }

    func addToMyVersions(_ translation: BibleTranslation) {
        guard !myVersionIds.contains(translation.id) else { return }
        myVersionIds.append(translation.id)
        UserDefaults.standard.set(myVersionIds, forKey: "myVersionIds")
    }

    func removeFromMyVersions(_ translation: BibleTranslation) {
        myVersionIds.removeAll { $0 == translation.id }
        UserDefaults.standard.set(myVersionIds, forKey: "myVersionIds")
    }

    // MARK: - Computed

    /// Books in the user's chosen order (canonical = Bible order, alphabetical = A–Z).
    var sortedBooks: [BibleBook] {
        bookSortOrder == .canonical
            ? books
            : books.sorted { $0.name < $1.name }
    }

    /// True if we're currently loading anything at all.
    var isLoading: Bool { isLoadingTranslations || isLoadingBooks || isLoadingContent }

    // MARK: - Private

    private let api = BibleAPIService()

    // MARK: - Public Actions

    /// Ensures translations + books are loaded before the caller proceeds.
    /// Safe to call from multiple concurrent tasks:
    ///   • If already fully loaded  → returns immediately (no-op).
    ///   • If currently loading     → waits for the in-progress fetch to finish.
    ///   • If not yet started       → kicks off the load and awaits it.
    /// This prevents the cold-start race where Search/Daily navigation arrives
    /// before the Reader tab has ever appeared and called this via .task.
    func loadInitialData() async {
        if isLoadingTranslations {
            // Another caller already started — wait for it instead of double-fetching.
            while isLoadingTranslations {
                try? await Task.sleep(for: .milliseconds(50))
            }
            return
        }
        guard translations.isEmpty else { return }
        await loadTranslations()
    }

    func loadTranslations() async {
        isLoadingTranslations = true
        errorMessage = nil
        defer { isLoadingTranslations = false }

        do {
            translations = try await api.fetchTranslations()
            await restoreOrDefaultTranslation()
        } catch let apiError as APIError {
            errorMessage = apiError.userMessage
        } catch is CancellationError {
            // Task was cancelled (e.g. user switched chapters quickly) — not a real error
        } catch {
            errorMessage = error.userMessage
        }
    }

    func selectTranslation(_ translation: BibleTranslation) async {
        selectedTranslation = translation
        lastBibleId = translation.id
        addToMyVersions(translation)
        // Reset downstream selections when translation changes
        selectedBook    = nil
        selectedChapter = nil
        chapterContent  = nil
        books           = []
        chapters        = []
        showTranslationBrowser = false
        await loadBooks(for: translation)
    }

    func selectBook(_ book: BibleBook) async {
        guard let translation = selectedTranslation else { return }
        lastBookId   = book.id
        selectedBook = book     // update book selector highlight immediately

        // ── Phase 1: silently fetch chapters ─────────────────────────────────
        let newChapters: [BibleChapter]
        do {
            newChapters = try await api.fetchChapters(bibleId: translation.id, bookId: book.id)
        } catch {
            errorMessage = "Couldn't load chapters for \(book.name)."
            return
        }
        guard !newChapters.isEmpty else { return }

        // ── Phase 2: determine target chapter (restore last visited, or first) ─
        let targetChapter = newChapters.first(where: { $0.id == lastChapterId }) ?? newChapters[0]
        lastChapterId = targetChapter.id

        // ── Phase 3: silently fetch content ───────────────────────────────────
        // isLoadingContent is NOT set — old content stays fully visible while
        // loading. The user sees no spinners or backend activity.
        let newContent: BibleChapterContent?
        do {
            newContent = try await api.fetchChapterContent(
                bibleId:   translation.id,
                chapterId: targetChapter.id
            )
        } catch {
            newContent = nil
            errorMessage = "Couldn't load \(targetChapter.reference). Try again."
        }

        // ── Phase 4a: spring-transition chapter chips into place ──────────────
        // selectedChapter still holds the old book's chapter ID, so none of the
        // new chips match — they all appear unselected. No blank/empty state.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            chapters = newChapters
        }

        // ── Phase 4b: one frame later — spring-select the target chip ─────────
        // The new chips now exist in the view hierarchy, so SwiftUI can animate
        // isSelected false → true on the matching chip with a proper spring.
        try? await Task.sleep(for: .milliseconds(50))
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            selectedChapter = targetChapter
            if let content = newContent {
                chapterContent   = content
                contentLoadCounter += 1
            }
        }
    }

    func selectChapter(_ chapter: BibleChapter) async {
        selectedChapter = chapter
        lastChapterId   = chapter.id
        await loadChapterContent(chapter)
    }

    func goToNextChapter() async {
        guard let current = selectedChapter,
              let idx = chapters.firstIndex(where: { $0.id == current.id }),
              idx + 1 < chapters.count
        else { return }
        await selectChapter(chapters[idx + 1])
    }

    func goToPreviousChapter() async {
        guard let current = selectedChapter,
              let idx = chapters.firstIndex(where: { $0.id == current.id }),
              idx > 0
        else { return }
        await selectChapter(chapters[idx - 1])
    }

    /// Navigates to the chapter identified by `chapterId` (e.g. "GEN.1").
    /// Called by ReaderView when the user taps "Open Chapter" from a handwriting search result.
    func navigateTo(chapterId: String) async {
        let parts  = chapterId.components(separatedBy: ".")
        guard !parts.isEmpty else { return }
        let bookId = parts[0]
        // Load books if not yet fetched (edge case: app launched on Search tab first).
        if books.isEmpty, let translation = selectedTranslation {
            await loadBooks(for: translation)
        }
        guard let book = books.first(where: { $0.id == bookId }) else { return }
        if selectedBook?.id != bookId {
            // Switching books: pre-set lastChapterId so selectBook's prefetch loads
            // the exact target chapter rather than the previously viewed chapter.
            lastChapterId = chapterId
            await selectBook(book)
        } else if let chapter = chapters.first(where: { $0.id == chapterId }) {
            // Same book: just switch to the target chapter.
            await selectChapter(chapter)
        }
    }

    // MARK: - Book Browser Support

    /// Fetches chapters for a book without changing the current selection.
    /// Used by BookBrowserView to show chapter grids for any book.
    func fetchChapters(for book: BibleBook) async -> [BibleChapter] {
        guard let translation = selectedTranslation else { return [] }
        return (try? await api.fetchChapters(bibleId: translation.id, bookId: book.id)) ?? []
    }

    /// Navigates directly to a specific book and chapter. Used by the book browser.
    func selectBookAndChapter(bookId: String, chapterId: String) async {
        lastChapterId = chapterId
        guard let book = books.first(where: { $0.id == bookId }) else { return }

        if selectedBook?.id == bookId {
            // Same book — just switch to the target chapter directly.
            if let chapter = chapters.first(where: { $0.id == chapterId }) {
                await selectChapter(chapter)
            }
        } else {
            // Different book — selectBook will use lastChapterId to pick the right chapter.
            await selectBook(book)
        }
    }

    // MARK: - Private Loaders

    private func loadBooks(for translation: BibleTranslation) async {
        isLoadingBooks = true
        errorMessage   = nil
        defer { isLoadingBooks = false }

        do {
            books = try await api.fetchBooks(bibleId: translation.id)
            await restoreOrDefaultBook()
        } catch {
            errorMessage = "Couldn't load books for this translation."
        }
    }

    private func loadChapterContent(_ chapter: BibleChapter) async {
        guard let translation = selectedTranslation else { return }
        isLoadingContent = true
        errorMessage     = nil
        defer { isLoadingContent = false }

        do {
            chapterContent = try await api.fetchChapterContent(
                bibleId:   translation.id,
                chapterId: chapter.id
            )
            contentLoadCounter += 1
        } catch {
            errorMessage = "Couldn't load \(chapter.reference). Try again."
        }
    }

    // MARK: - Restore Last Session

    private func restoreOrDefaultTranslation() async {
        // Try to go back to where the user left off. If not found, default to KJV or first available.
        if let last = translations.first(where: { $0.id == lastBibleId }) {
            await selectTranslation(last)
        } else if let kjv = translations.first(where: {
            $0.abbreviation.uppercased().contains("KJV") && $0.isEnglish
        }) {
            await selectTranslation(kjv)
        } else if let first = translations.first {
            await selectTranslation(first)
        }
    }

    private func restoreOrDefaultBook() async {
        if let last = books.first(where: { $0.id == lastBookId }) {
            await selectBook(last)
        } else if let genesis = books.first {
            await selectBook(genesis)
        }
    }

}
