//
//  BookmarksViewModel.swift
//  ScriptureScribe
//
//  Manages all bookmarks and bookmark groups for the app.
//
//  Storage strategy:
//  • Always saved to UserDefaults (works offline, no sign-in required).
//  • When the user is signed in, every add/delete is also mirrored to Firestore.
//  • On sign-in, Firestore bookmarks and groups are fetched and merged with any
//    local ones — the local data is uploaded, and any Firestore-only data is
//    added locally. This keeps all devices in sync.
//

import Combine
import SwiftUI

@MainActor
final class BookmarksViewModel: ObservableObject {

    @Published var bookmarks: [Bookmark]      = []
    @Published var groups:    [BookmarkGroup] = []

    private let storageKey       = "scripture_scribe_bookmarks"
    private let groupsStorageKey = "scripture_scribe_bookmark_groups"
    private let firestore        = FirestoreService()

    init() {
        load()
        loadGroups()
    }

    // MARK: - Sync with Firestore

    /// Call this when the user signs in. Downloads cloud bookmarks + groups and merges
    /// them with whatever is stored locally on this device.
    func syncOnSignIn(userId: String) async {
        // ── Bookmarks ──────────────────────────────────────────────────────────
        let cloudBookmarks = (try? await firestore.fetchBookmarks(userId: userId)) ?? []

        // Upload any local bookmarks that aren't in the cloud yet
        for local in bookmarks {
            if !cloudBookmarks.contains(where: { $0.id == local.id }) {
                try? await firestore.saveBookmark(local, userId: userId)
            }
        }
        // Add any cloud bookmarks that aren't on this device
        for cloud in cloudBookmarks {
            if !bookmarks.contains(where: { $0.id == cloud.id }) {
                bookmarks.append(cloud)
            }
        }
        save()

        // ── Groups ─────────────────────────────────────────────────────────────
        let cloudGroups = (try? await firestore.fetchBookmarkGroups(userId: userId)) ?? []

        for local in groups {
            if !cloudGroups.contains(where: { $0.id == local.id }) {
                try? await firestore.saveBookmarkGroup(local, userId: userId)
            }
        }
        for cloud in cloudGroups {
            if !groups.contains(where: { $0.id == cloud.id }) {
                groups.append(cloud)
            }
        }
        saveGroups()
    }

    // MARK: - Bookmark Queries

    /// Returns true if the given chapter is already bookmarked at the chapter level.
    func isBookmarked(chapterId: String) -> Bool {
        bookmarks.contains { $0.chapterId == chapterId && $0.verseId.isEmpty }
    }

    /// Returns true if a specific verse has already been bookmarked.
    func isVerseBookmarked(chapterId: String, verseId: String) -> Bool {
        bookmarks.contains { $0.chapterId == chapterId && $0.verseId == verseId }
    }

    // MARK: - Bookmark Actions

    /// Saves a new bookmark.  When verseId is non-empty this is a verse-level
    /// bookmark.  If verseIdEnd is also non-empty, this is a verse range bookmark.
    /// When verseId is empty it is a chapter-level bookmark.
    func addBookmark(
        bibleId:      String,
        bookId:       String,
        chapter:      BibleChapter,
        verseNumbers: [String] = [],
        verseText:    String   = "",
        colorHex:     String,
        emoji:        String,
        groupIds:     [String] = [],
        userId:       String?  = nil
    ) {
        // Build the display reference using smart grouping: "Genesis 1: 1-3, 5"
        let ref: String
        if verseNumbers.isEmpty {
            ref = chapter.reference
        } else {
            ref = "\(chapter.reference): \(Bookmark.formatVerseList(verseNumbers))"
        }

        let firstVerse = verseNumbers.first ?? ""

        // Deduplicate: don't allow the exact same verse to be bookmarked twice.
        if firstVerse.isEmpty {
            guard !isBookmarked(chapterId: chapter.id) else { return }
        } else {
            guard !isVerseBookmarked(chapterId: chapter.id, verseId: firstVerse) else { return }
        }

        let bookmark = Bookmark(
            bibleId:          bibleId,
            bookId:           bookId,
            chapterId:        chapter.id,
            chapterReference: ref,
            verseId:          firstVerse,
            verseIdEnd:       verseNumbers.last ?? "",
            verseNumbers:     verseNumbers,
            verseText:        verseText,
            colorHex:         colorHex,
            emoji:            emoji,
            groupIds:         groupIds,
            createdAt:        Date()
        )
        bookmarks.append(bookmark)
        save()

        if let userId {
            Task { try? await firestore.saveBookmark(bookmark, userId: userId) }
        }
    }

    /// Removes the bookmark for the given chapter (if one exists).
    func removeBookmark(for chapterId: String, userId: String? = nil) {
        let toRemove = bookmarks.filter { $0.chapterId == chapterId }
        bookmarks.removeAll { $0.chapterId == chapterId }
        save()

        if let userId {
            for b in toRemove {
                Task { try? await firestore.deleteBookmark(id: b.id, userId: userId) }
            }
        }
    }

    /// Removes a bookmark by its ID (used in the list view for swipe-to-delete).
    func removeBookmark(id: String, userId: String? = nil) {
        bookmarks.removeAll { $0.id == id }
        save()

        if let userId {
            Task { try? await firestore.deleteBookmark(id: id, userId: userId) }
        }
    }

    // MARK: - Group Actions

    /// Creates a new group. If a group with the same name already exists, returns it without duplicating.
    @discardableResult
    func addGroup(
        name:     String,
        colorHex: String,
        emoji:    String,
        userId:   String? = nil
    ) -> BookmarkGroup {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = groups.first(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) { return existing }

        let group = BookmarkGroup(name: trimmed, colorHex: colorHex, emoji: emoji)
        groups.append(group)
        saveGroups()

        if let userId {
            Task { try? await firestore.saveBookmarkGroup(group, userId: userId) }
        }
        return group
    }

    /// Updates a group's name, color, and emoji.
    func updateGroup(id: String, name: String, colorHex: String, emoji: String, userId: String? = nil) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name     = name
        groups[index].colorHex = colorHex
        groups[index].emoji    = emoji
        saveGroups()
        if let userId {
            Task { try? await firestore.saveBookmarkGroup(groups[index], userId: userId) }
        }
    }

    /// Deletes a group and removes it from any bookmarks that belonged to it.
    func deleteGroup(id: String, userId: String? = nil) {
        groups.removeAll { $0.id == id }
        // Remove this group from all bookmarks that reference it
        for index in bookmarks.indices {
            bookmarks[index].groupIds.removeAll { $0 == id }
        }
        saveGroups()
        save()

        if let userId {
            Task { try? await firestore.deleteBookmarkGroup(id: id, userId: userId) }
        }
    }

    /// Updates the verse range and text of a bookmark.
    func updateBookmarkVerses(
        id:               String,
        verseId:          String,
        verseIdEnd:       String,
        verseText:        String,
        chapterReference: String,
        userId:           String? = nil
    ) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].verseId          = verseId
        bookmarks[index].verseIdEnd       = verseIdEnd
        bookmarks[index].verseText        = verseText
        bookmarks[index].chapterReference = chapterReference
        save()
        if let userId {
            Task { try? await firestore.saveBookmark(bookmarks[index], userId: userId) }
        }
    }

    /// Updates a bookmark's emoji and color.
    func updateBookmark(id: String, colorHex: String, emoji: String, userId: String? = nil) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].colorHex = colorHex
        bookmarks[index].emoji    = emoji
        save()
        if let userId {
            Task { try? await firestore.saveBookmark(bookmarks[index], userId: userId) }
        }
    }

    /// Adds or removes a single group from a bookmark's groupIds.
    func toggleGroup(bookmarkId: String, groupId: String, userId: String? = nil) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkId }) else { return }
        if bookmarks[index].groupIds.contains(groupId) {
            bookmarks[index].groupIds.removeAll { $0 == groupId }
        } else {
            bookmarks[index].groupIds.append(groupId)
        }
        save()
        if let userId {
            Task { try? await firestore.saveBookmark(bookmarks[index], userId: userId) }
        }
    }

    /// Sets a bookmark's groupIds to the given array.
    func setGroups(bookmarkId: String, groupIds: [String], userId: String? = nil) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkId }) else { return }
        bookmarks[index].groupIds = groupIds
        save()
        if let userId {
            Task { try? await firestore.saveBookmark(bookmarks[index], userId: userId) }
        }
    }

    /// Moves a bookmark from one group to another (removes old, adds new).
    func moveBookmark(id: String, from oldGroupId: String?, to newGroupId: String?, userId: String? = nil) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        if let old = oldGroupId {
            bookmarks[index].groupIds.removeAll { $0 == old }
        }
        if let new = newGroupId, !bookmarks[index].groupIds.contains(new) {
            bookmarks[index].groupIds.append(new)
        }
        save()
        if let userId {
            Task { try? await firestore.saveBookmark(bookmarks[index], userId: userId) }
        }
    }

    // MARK: - Persistence (UserDefaults)

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

    private func saveGroups() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: groupsStorageKey)
    }

    private func loadGroups() {
        guard
            let data  = UserDefaults.standard.data(forKey: groupsStorageKey),
            let saved = try? JSONDecoder().decode([BookmarkGroup].self, from: data)
        else { return }
        groups = saved
    }
}
