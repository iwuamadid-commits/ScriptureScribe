//
//  BookmarksViewModel.swift
//  ScriptureScribe
//
//  Manages all bookmarks for the app.
//  Bookmarks are saved to UserDefaults so they survive app restarts.
//  Firebase sync will be added in Phase 6 once user login is built.
//

import Combine
import SwiftUI

@MainActor
final class BookmarksViewModel: ObservableObject {

    @Published var bookmarks: [Bookmark] = []

    private let storageKey = "scripture_scribe_bookmarks"

    init() {
        load()
    }

    // MARK: - Public Queries

    /// Returns true if the given chapter is already bookmarked at the chapter level.
    func isBookmarked(chapterId: String) -> Bool {
        bookmarks.contains { $0.chapterId == chapterId && $0.verseId.isEmpty }
    }

    /// Returns true if a specific verse has already been bookmarked.
    func isVerseBookmarked(chapterId: String, verseId: String) -> Bool {
        bookmarks.contains { $0.chapterId == chapterId && $0.verseId == verseId }
    }

    // MARK: - Public Actions

    /// Saves a new bookmark. When verseId is non-empty this is a verse-level
    /// bookmark — multiple verses in the same chapter can each be bookmarked
    /// independently. When verseId is empty it is a chapter-level bookmark.
    func addBookmark(
        bibleId:   String,
        bookId:    String,
        chapter:   BibleChapter,
        verseId:   String = "",
        verseText: String = "",
        colorHex:  String,
        emoji:     String
    ) {
        // Build the display reference: "Genesis 1" or "Genesis 1 v3"
        let ref = verseId.isEmpty
            ? chapter.reference
            : "\(chapter.reference) v\(verseId)"

        // Deduplicate: don't allow the exact same verse to be bookmarked twice.
        // (For chapter-level bookmarks: one per chapter. For verse-level: one per verse.)
        if verseId.isEmpty {
            guard !isBookmarked(chapterId: chapter.id) else { return }
        } else {
            guard !isVerseBookmarked(chapterId: chapter.id, verseId: verseId) else { return }
        }

        let bookmark = Bookmark(
            bibleId:          bibleId,
            bookId:           bookId,
            chapterId:        chapter.id,
            chapterReference: ref,
            verseId:          verseId,
            verseText:        verseText,
            colorHex:         colorHex,
            emoji:            emoji,
            createdAt:        Date()
        )
        bookmarks.append(bookmark)
        save()
    }

    /// Removes the bookmark for the given chapter (if one exists).
    func removeBookmark(for chapterId: String) {
        bookmarks.removeAll { $0.chapterId == chapterId }
        save()
    }

    /// Removes a bookmark by its ID (used in the list view for swipe-to-delete).
    func removeBookmark(id: String) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data  = UserDefaults.standard.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode([Bookmark].self, from: data)
        else { return }
        bookmarks = saved
    }
}
