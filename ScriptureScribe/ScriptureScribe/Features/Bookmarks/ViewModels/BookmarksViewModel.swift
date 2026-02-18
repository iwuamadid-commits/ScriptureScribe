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

    /// Returns true if the given chapter is already bookmarked.
    func isBookmarked(chapterId: String) -> Bool {
        bookmarks.contains { $0.chapterId == chapterId }
    }

    // MARK: - Public Actions

    /// Saves a new bookmark for the given chapter with the chosen color and emoji.
    func addBookmark(
        bibleId:   String,
        bookId:    String,
        chapter:   BibleChapter,
        colorHex:  String,
        emoji:     String
    ) {
        // Don't add duplicates
        guard !isBookmarked(chapterId: chapter.id) else { return }
        let bookmark = Bookmark(
            bibleId:          bibleId,
            bookId:           bookId,
            chapterId:        chapter.id,
            chapterReference: chapter.reference,
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
