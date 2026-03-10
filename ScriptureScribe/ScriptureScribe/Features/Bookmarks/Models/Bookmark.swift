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
    var chapterReference: String   // e.g. "Genesis 1: 3, 5" — for display in the list
    var verseId:          String   // first verse number, or "" for a chapter-level bookmark
    var verseIdEnd:       String   // end of range (legacy), or "" for single verse
    var verseNumbers:     [String] // individual selected verse numbers, e.g. ["1","3","5"]
    var verseText:        String   // the verse text (combined for selected verses only), or "" for chapter
    var colorHex:         String   // e.g. "FF5733" — the ribbon color the user chose
    var emoji:            String   // e.g. "⭐" — the emoji the user chose
    var groupIds:         [String] // empty = ungrouped; contains BookmarkGroup.id values when assigned
    let createdAt:        Date

    // Custom init so callers can omit verseId/verseIdEnd/verseText/groupIds (all default to "" or [])
    init(
        id:               String   = UUID().uuidString,
        bibleId:          String,
        bookId:           String,
        chapterId:        String,
        chapterReference: String,
        verseId:          String   = "",
        verseIdEnd:       String   = "",
        verseNumbers:     [String] = [],
        verseText:        String   = "",
        colorHex:         String,
        emoji:            String,
        groupIds:         [String] = [],
        createdAt:        Date
    ) {
        self.id               = id
        self.bibleId          = bibleId
        self.bookId           = bookId
        self.chapterId        = chapterId
        self.chapterReference = chapterReference
        self.verseId          = verseId
        self.verseIdEnd       = verseIdEnd
        self.verseNumbers     = verseNumbers
        self.verseText        = verseText
        self.colorHex         = colorHex
        self.emoji            = emoji
        self.groupIds         = groupIds
        self.createdAt        = createdAt
    }

    // Backward-compatible decoder: older bookmarks won't have verseNumbers
    enum CodingKeys: String, CodingKey {
        case id, bibleId, bookId, chapterId, chapterReference
        case verseId, verseIdEnd, verseNumbers, verseText
        case colorHex, emoji, groupId, groupIds, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try  c.decode(String.self,    forKey: .id)
        bibleId          = try  c.decode(String.self,    forKey: .bibleId)
        bookId           = try  c.decode(String.self,    forKey: .bookId)
        chapterId        = try  c.decode(String.self,    forKey: .chapterId)
        chapterReference = try  c.decode(String.self,    forKey: .chapterReference)
        verseId          = try  c.decode(String.self,    forKey: .verseId)
        verseIdEnd       = (try? c.decode(String.self,   forKey: .verseIdEnd)) ?? ""
        verseText        = try  c.decode(String.self,    forKey: .verseText)
        colorHex         = try  c.decode(String.self,    forKey: .colorHex)
        emoji            = try  c.decode(String.self,    forKey: .emoji)
        createdAt        = try  c.decode(Date.self,      forKey: .createdAt)

        // Backward compat: migrate old single groupId to groupIds array
        if let ids = try? c.decode([String].self, forKey: .groupIds), !ids.isEmpty {
            groupIds = ids
        } else if let singleId = try? c.decode(String.self, forKey: .groupId), !singleId.isEmpty {
            groupIds = [singleId]
        } else {
            groupIds = []
        }

        // Backward compat: reconstruct verseNumbers from verseId/verseIdEnd if missing
        if let nums = try? c.decode([String].self, forKey: .verseNumbers), !nums.isEmpty {
            verseNumbers = nums
        } else if !verseId.isEmpty {
            if let start = Int(verseId), let end = Int(verseIdEnd), end > start {
                verseNumbers = (start...end).map { String($0) }
            } else {
                verseNumbers = [verseId]
            }
        } else {
            verseNumbers = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,               forKey: .id)
        try c.encode(bibleId,          forKey: .bibleId)
        try c.encode(bookId,           forKey: .bookId)
        try c.encode(chapterId,        forKey: .chapterId)
        try c.encode(chapterReference, forKey: .chapterReference)
        try c.encode(verseId,          forKey: .verseId)
        try c.encode(verseIdEnd,       forKey: .verseIdEnd)
        try c.encode(verseNumbers,     forKey: .verseNumbers)
        try c.encode(verseText,        forKey: .verseText)
        try c.encode(colorHex,         forKey: .colorHex)
        try c.encode(emoji,            forKey: .emoji)
        try c.encode(groupIds,         forKey: .groupIds)
        try c.encode(createdAt,        forKey: .createdAt)
    }

    /// The verse numbers to highlight when navigating to this bookmark in the reader.
    var resolvedVerseNumbers: [String] {
        if !verseNumbers.isEmpty { return verseNumbers }
        if !verseId.isEmpty {
            if let start = Int(verseId), let end = Int(verseIdEnd), end > start {
                return (start...end).map { String($0) }
            }
            return [verseId]
        }
        return []
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

    /// Formats verse numbers with smart grouping: ["1","2","3","5","7","8"] → "1-3, 5, 7-8"
    static func formatVerseList(_ numbers: [String]) -> String {
        let sorted = numbers.compactMap { Int($0) }.sorted()
        guard !sorted.isEmpty else { return numbers.joined(separator: ", ") }
        var parts: [String] = []
        var rangeStart = sorted[0]
        var rangeEnd   = sorted[0]
        for i in 1..<sorted.count {
            if sorted[i] == rangeEnd + 1 {
                rangeEnd = sorted[i]
            } else {
                parts.append(rangeStart == rangeEnd ? "\(rangeStart)" : "\(rangeStart)-\(rangeEnd)")
                rangeStart = sorted[i]
                rangeEnd   = sorted[i]
            }
        }
        parts.append(rangeStart == rangeEnd ? "\(rangeStart)" : "\(rangeStart)-\(rangeEnd)")
        return parts.joined(separator: ", ")
    }
}
