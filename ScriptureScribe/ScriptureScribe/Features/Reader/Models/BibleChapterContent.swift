//
//  BibleChapterContent.swift
//  ScriptureScribe
//
//  Holds the actual text content of a fetched chapter, ready to display.
//

import Foundation

// MARK: - Red Letter Support

/// One run of text inside a verse — either normal or spoken by Jesus.
struct VerseSegment {
    let text:        String
    let isRedLetter: Bool
}

/// A single verse broken into colored segments.
struct ParsedVerse {
    let number:   String           // e.g. "16"
    let segments: [VerseSegment]
}

// MARK: - Chapter Content

struct BibleChapterContent {
    let id:           String       // e.g. "GEN.1"
    let bibleId:      String
    let bookId:       String
    let number:       String
    let reference:    String       // e.g. "Genesis 1" — shown as the page title
    let textContent:  String       // full plain text with [N] verse markers inline
    let copyright:    String       // must be displayed on every chapter — licensing requirement
    var parsedVerses: [ParsedVerse] = []  // structured verses for red-letter rendering
}
