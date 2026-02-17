//
//  BibleChapterContent.swift
//  ScriptureScribe
//
//  Holds the actual text content of a fetched chapter, ready to display.
//

import Foundation

struct BibleChapterContent {
    let id: String          // e.g. "GEN.1"
    let bibleId: String
    let bookId: String
    let number: String
    let reference: String   // e.g. "Genesis 1" — shown as the page title
    let textContent: String // the full readable text of this chapter (with verse numbers inline)
    let copyright: String   // must be displayed on every chapter — licensing requirement
}
