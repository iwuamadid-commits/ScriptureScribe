//
//  VerseHighlight.swift
//  ScriptureScribe
//
//  A colored highlight the user painted over one verse with their finger,
//  the way the Bible app works.
//
//  Deliberately one record PER VERSE rather than one per selection: the user
//  can highlight verses 1, 3 and 7 in one gesture, but storing them separately
//  keeps recoloring and clearing a single verse trivial, with no ranges to
//  split or merge.
//
//  This is NOT the same thing as a Bookmark (which also carries a color).
//  A bookmark is a saved place the user returns to and appears in their
//  Library; a highlight is just ink on the page.
//

import Foundation

struct VerseHighlight: Identifiable, Codable, Equatable {

    let chapterId:   String   // e.g. "JHN.3"
    let verseNumber: String   // e.g. "16" — matches ParsedVerse.number
    var colorHex:    String   // e.g. "F5C842", one of Bookmark.presetColors
    let createdAt:   Date

    /// Derived from the verse itself, not random.
    ///
    /// One document per verse means the iPad and the iPhone highlighting the
    /// same verse while both offline produce the SAME id, so the later sync
    /// overwrites rather than leaving the verse with two colors. A UUID here
    /// would need duplicate-resolution logic on every sign-in.
    var id: String { Self.id(chapterId: chapterId, verseNumber: verseNumber) }

    static func id(chapterId: String, verseNumber: String) -> String {
        "\(chapterId):\(verseNumber)"
    }

    init(
        chapterId:   String,
        verseNumber: String,
        colorHex:    String,
        createdAt:   Date = Date()
    ) {
        self.chapterId   = chapterId
        self.verseNumber = verseNumber
        self.colorHex    = colorHex
        self.createdAt   = createdAt
    }

    // `id` is computed, so it is neither encoded nor decoded.
    enum CodingKeys: String, CodingKey {
        case chapterId, verseNumber, colorHex, createdAt
    }

    // MARK: - Colors

    /// Highlights reuse the bookmark palette so the two features feel related
    /// and the user only ever learns one set of colors.
    static var presetColors: [(name: String, hex: String)] { Bookmark.presetColors }

    /// How strongly the color is painted behind the text.
    ///
    /// Never a solid fill — the text has to stay readable through it.
    ///
    /// Dark themes need MORE of the color, not less. These are mid-tone ribbon
    /// colors, and at light-theme strength over a near-black page they
    /// composite down to a muddy olive or navy that reads as a smudge rather
    /// than a highlight.
    static func fillOpacity(onDarkTheme: Bool) -> Double {
        onDarkTheme ? 0.55 : 0.35
    }
}
