//
//  Bookmark.swift
//  ScriptureScribe
//
//  Represents a single bookmarked Bible chapter.
//  Stored locally on the device (synced to Firebase in Phase 6 when login is complete).
//

import Foundation

struct Bookmark: Identifiable, Codable {

    var id:               String = UUID().uuidString
    let bibleId:          String
    let bookId:           String
    let chapterId:        String
    let chapterReference: String   // e.g. "Genesis 1" — for display in the list
    var colorHex:         String   // e.g. "FF5733" — the ribbon color the user chose
    var emoji:            String   // e.g. "⭐" — the emoji the user chose
    let createdAt:        Date

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
