//
//  Bookmark.swift
//  ScriptureScribe
//
//  Represents a single bookmarked Bible verse (or chapter).
//  verseId / verseText are optional fields for verse-level bookmarks;
//  both default to "" so old saved data (chapter-level) still decodes fine.
//  Stored locally on the device (synced to Firebase in Phase 6 when login is complete).
//

import Foundation

struct Bookmark: Identifiable, Codable {

    var id:               String = UUID().uuidString
    let bibleId:          String
    let bookId:           String
    let chapterId:        String
    let chapterReference: String   // e.g. "Genesis 1 v3-5" — for display in the list
    var verseId:          String   // verse number, or "" for a chapter-level bookmark
    var verseIdEnd:       String   // end of range (e.g. "5" for v3-5), or "" for single verse
    var verseText:        String   // the verse text (or combined text for range), or "" for chapter
    var colorHex:         String   // e.g. "FF5733" — the ribbon color the user chose
    var emoji:            String   // e.g. "⭐" — the emoji the user chose
    let createdAt:        Date

    // Custom init so callers can omit verseId/verseIdEnd/verseText (defaults to "")
    init(
        id:               String = UUID().uuidString,
        bibleId:          String,
        bookId:           String,
        chapterId:        String,
        chapterReference: String,
        verseId:          String = "",
        verseIdEnd:       String = "",
        verseText:        String = "",
        colorHex:         String,
        emoji:            String,
        createdAt:        Date
    ) {
        self.id               = id
        self.bibleId          = bibleId
        self.bookId           = bookId
        self.chapterId        = chapterId
        self.chapterReference = chapterReference
        self.verseId          = verseId
        self.verseIdEnd       = verseIdEnd
        self.verseText        = verseText
        self.colorHex         = colorHex
        self.emoji            = emoji
        self.createdAt        = createdAt
    }

    // MARK: - Preset Colors

    /// The 8 colors the user can pick when bookmarking.
    static let presetColors: [(name: String, hex: String)] = [
        ("Gold",   "F5C842"),
        ("Red",    "E84040"),
        ("Orange", "E87040"),
        ("Green",  "5C8A6B"),
        ("Blue",   "4A7EC8"),
        ("Purple", "8B7EC8"),
        ("Pink",   "E87EA0"),
        ("Slate",  "7A8A9A"),
    ]

    // MARK: - Preset Emojis

    /// The emojis the user can attach to a bookmark.
    static let presetEmojis = ["⭐", "🔖", "✝️", "🙏", "❤️", "💡", "🌟", "📖", "🕊️", "🔥"]
}
