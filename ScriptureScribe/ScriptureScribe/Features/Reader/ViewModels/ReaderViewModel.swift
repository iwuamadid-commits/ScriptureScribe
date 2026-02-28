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

    /// Call this once when the Reader tab first appears.
    func loadInitialData() async {
        guard translations.isEmpty else { return } // already loaded
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
            errorMessage = "API error: \(apiError.errorDescription ?? "unknown")"
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }
    }

    func selectTranslation(_ translation: BibleTranslation) async {
        selectedTranslation = translation
        lastBibleId = translation.id
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
        selectedBook    = book
        selectedChapter = nil
        // Keep chapterContent as-is while the new chapter loads so the screen
        // never goes blank — the old text fades out when new content arrives.
        chapters        = []
        lastBookId      = book.id
        await loadChapters(for: book)
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
        // Only reload book+chapters if we're switching to a different book.
        if selectedBook?.id != bookId { await selectBook(book) }
        // After selectBook, chapters is populated; select the target.
        if let chapter = chapters.first(where: { $0.id == chapterId }) {
            await selectChapter(chapter)
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

    private func loadChapters(for book: BibleBook) async {
        guard let translation = selectedTranslation else { return }
        errorMessage = nil

        do {
            chapters = try await api.fetchChapters(bibleId: translation.id, bookId: book.id)
            await restoreOrDefaultChapter()
        } catch {
            errorMessage = "Couldn't load chapters for \(book.name)."
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

    private func restoreOrDefaultChapter() async {
        if let last = chapters.first(where: { $0.id == lastChapterId }) {
            await selectChapter(last)
        } else if let first = chapters.first {
            await selectChapter(first)
        }
    }
}
