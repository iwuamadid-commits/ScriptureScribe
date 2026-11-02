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
    /// Persisted so the user's choice survives the app being relaunched.
    @Published var bookSortOrder: SortOrder =
        SortOrder(rawValue: UserDefaults.standard.string(forKey: "bookSortOrder") ?? "") ?? .canonical {
        didSet { UserDefaults.standard.set(bookSortOrder.rawValue, forKey: "bookSortOrder") }
    }

    enum SortOrder: String { case canonical, alphabetical }

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
    private let firestore = FirestoreService()
    /// Tracks the in-flight selectBook/selectChapter task so a new navigation
    /// cancels any previous one — prevents stale content from overwriting fresh content.
    private var navigationTask: Task<Void, Never>?

    // MARK: - Cloud Sync

    func syncToCloud(userId: String) async {
        let data: [String: Any] = [
            "lastBibleId": lastBibleId,
            "lastBookId": lastBookId,
            "lastChapterId": lastChapterId,
            "myVersionIds": myVersionIds
        ]
        try? await firestore.saveSyncData(data, userId: userId)
    }

    /// The account whose cloud data has already been restored. ReaderView's .task
    /// re-runs every time the Reader tab reappears, so without this the restore
    /// would repeat on every tab switch.
    private var restoredCloudUserId: String?

    func restoreFromCloud(userId: String) async {
        guard restoredCloudUserId != userId else { return }
        guard let data = try? await firestore.fetchSyncData(userId: userId) else { return }
        restoredCloudUserId = userId

        // The cloud reading position is only a starting point for a fresh launch.
        // Once the reader has started loading, lastBookId/lastChapterId must keep
        // matching the chapter on screen, because selectTranslation reopens them.
        // Overwriting them with the older cloud copy would send a version switch
        // back to that older chapter.
        let readerHasStarted = !translations.isEmpty || isLoadingTranslations
        if !readerHasStarted {
            if let bibleId = data["lastBibleId"] as? String, !bibleId.isEmpty {
                lastBibleId = bibleId
            }
            if let bookId = data["lastBookId"] as? String, !bookId.isEmpty {
                lastBookId = bookId
            }
            if let chapterId = data["lastChapterId"] as? String, !chapterId.isEmpty {
                lastChapterId = chapterId
            }
        }
        if let versions = data["myVersionIds"] as? [String], !versions.isEmpty {
            // Merge cloud versions with local (preserve order, no duplicates)
            var merged = myVersionIds
            for id in versions where !merged.contains(id) {
                merged.append(id)
            }
            myVersionIds = merged
            UserDefaults.standard.set(myVersionIds, forKey: "myVersionIds")
        }
    }

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

    // MARK: - Chapter History (back / forward)
    //
    // Records only deliberate jumps — tapping a book or chapter, opening a search
    // result, or picking from the book browser. Swiping between consecutive
    // chapters is NOT recorded, so Back stays useful instead of just repeating
    // what a swipe already does.

    @Published private(set) var backStack:    [String] = []
    @Published private(set) var forwardStack: [String] = []

    private let maxHistoryDepth = 50

    var canGoBack:    Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Readable label for where Back would take the reader, e.g. "John 4".
    var backDestination:    String? { backStack.last.flatMap(displayReference(forChapterId:)) }
    /// Readable label for where Forward would take the reader.
    var forwardDestination: String? { forwardStack.last.flatMap(displayReference(forChapterId:)) }

    /// Turns a chapter id ("JHN.4") into a human reference ("John 4"). Uses the
    /// loaded chapter when it's in the current book, otherwise builds the label
    /// from the book list so cross-book destinations still read properly.
    func displayReference(forChapterId chapterId: String) -> String? {
        if let chapter = chapters.first(where: { $0.id == chapterId }) {
            return chapter.reference
        }
        let parts = chapterId.components(separatedBy: ".")
        guard parts.count >= 2,
              let book = books.first(where: { $0.id == parts[0] })
        else { return nil }
        let number = parts[1]
        return number.caseInsensitiveCompare("intro") == .orderedSame
            ? "\(book.name) Intro"
            : "\(book.name) \(number)"
    }

    /// Pushes the chapter being left onto the back stack. Passing the destination
    /// avoids recording a "jump" that lands on the chapter already being shown.
    private func recordDeparture(to destinationId: String?) {
        guard let current = selectedChapter?.id, current != destinationId else { return }
        backStack.append(current)
        if backStack.count > maxHistoryDepth { backStack.removeFirst() }
        // Any new jump invalidates the forward trail, exactly like a browser.
        forwardStack.removeAll()
    }

    /// Returns to the chapter visited before the current one.
    func goBack() async {
        guard let target = backStack.popLast() else { return }
        if let current = selectedChapter?.id { forwardStack.append(current) }
        await navigateTo(chapterId: target, recordHistory: false)
    }

    /// Returns to the chapter left behind by `goBack()`.
    func goForward() async {
        guard let target = forwardStack.popLast() else { return }
        if let current = selectedChapter?.id { backStack.append(current) }
        await navigateTo(chapterId: target, recordHistory: false)
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
        // Chapter ids are translation-specific, so a trail from the previous
        // translation would point at chapters that no longer resolve.
        backStack.removeAll()
        forwardStack.removeAll()
        showTranslationBrowser = false
        await loadBooks(for: translation)
    }

    /// - Parameter recordHistory: false when called as part of a larger navigation
    ///   that has already recorded the departure (or when stepping back/forward).
    func selectBook(_ book: BibleBook, recordHistory: Bool = true) async {
        navigationTask?.cancel()
        guard let translation = selectedTranslation else { return }
        if recordHistory { recordDeparture(to: nil) }
        lastBookId   = book.id
        selectedBook = book     // update book selector highlight immediately

        let task = Task {
            // ── Phase 1: silently fetch chapters ─────────────────────────────────
            let newChapters: [BibleChapter]
            do {
                newChapters = try await api.fetchChapters(bibleId: translation.id, bookId: book.id)
            } catch {
                if !Task.isCancelled { errorMessage = "Couldn't load chapters for \(book.name)." }
                return
            }
            guard !Task.isCancelled, !newChapters.isEmpty else { return }

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
                if !Task.isCancelled { errorMessage = "Couldn't load \(targetChapter.reference). Try again." }
            }
            guard !Task.isCancelled else { return }

            // ── Phase 4a: spring-transition chapter chips into place ──────────────
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                chapters = newChapters
            }

            // ── Phase 4b: select the target chip (triggers fade-out in ReaderView) ─
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedChapter = targetChapter
            }

            // ── Phase 4c: swap content after the fade-out completes ─────────────
            if let content = newContent {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                chapterContent     = content
                contentLoadCounter += 1
            }
        }
        navigationTask = task
        await task.value
    }

    /// - Parameter recordHistory: false for swipes between consecutive chapters and
    ///   for internal steps of a jump whose departure was already recorded.
    func selectChapter(_ chapter: BibleChapter, recordHistory: Bool = true) async {
        navigationTask?.cancel()
        if recordHistory { recordDeparture(to: chapter.id) }
        selectedChapter = chapter
        lastChapterId   = chapter.id

        let task = Task {
            // Wait for the fade-out animation (0.2s) to finish before loading new content
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await loadChapterContent(chapter)
        }
        navigationTask = task
        await task.value
    }

    func goToNextChapter() async {
        guard let current = selectedChapter,
              let idx = chapters.firstIndex(where: { $0.id == current.id }),
              idx + 1 < chapters.count
        else { return }
        // Page-turning, not a jump — deliberately not recorded in history.
        await selectChapter(chapters[idx + 1], recordHistory: false)
    }

    func goToPreviousChapter() async {
        guard let current = selectedChapter,
              let idx = chapters.firstIndex(where: { $0.id == current.id }),
              idx > 0
        else { return }
        // Page-turning, not a jump — deliberately not recorded in history.
        await selectChapter(chapters[idx - 1], recordHistory: false)
    }

    /// Navigates to the chapter identified by `chapterId` (e.g. "GEN.1").
    /// Called by ReaderView when the user taps "Open Chapter" from a handwriting search result.
    /// - Parameter recordHistory: false when stepping through the back/forward trail,
    ///   so the step itself isn't recorded as a new jump.
    func navigateTo(chapterId: String, recordHistory: Bool = true) async {
        let parts  = chapterId.components(separatedBy: ".")
        guard !parts.isEmpty else { return }
        let bookId = parts[0]
        // Load books if not yet fetched (edge case: app launched on Search tab first).
        if books.isEmpty, let translation = selectedTranslation {
            await loadBooks(for: translation)
        }
        guard let book = books.first(where: { $0.id == bookId }) else { return }
        if recordHistory { recordDeparture(to: chapterId) }
        if selectedBook?.id != bookId {
            // Switching books: pre-set lastChapterId so selectBook's prefetch loads
            // the exact target chapter rather than the previously viewed chapter.
            lastChapterId = chapterId
            await selectBook(book, recordHistory: false)
        } else if let chapter = chapters.first(where: { $0.id == chapterId }) {
            // Same book: just switch to the target chapter.
            await selectChapter(chapter, recordHistory: false)
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
        guard let book = books.first(where: { $0.id == bookId }) else { return }
        recordDeparture(to: chapterId)
        lastChapterId = chapterId

        if selectedBook?.id == bookId {
            // Same book — just switch to the target chapter directly.
            if let chapter = chapters.first(where: { $0.id == chapterId }) {
                await selectChapter(chapter, recordHistory: false)
            }
        } else {
            // Different book — selectBook will use lastChapterId to pick the right chapter.
            await selectBook(book, recordHistory: false)
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
