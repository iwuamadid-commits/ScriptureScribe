//
//  BibleChapter.swift
//  ScriptureScribe
//
//  Represents a single chapter within a Bible book (e.g. Genesis 1, John 3).
//

import Foundation

struct BibleChapter: Identifiable, Codable, Hashable {
    let id: String        // e.g. "GEN.1", "JHN.3" — used in API calls
    let bibleId: String
    let bookId: String    // e.g. "GEN", "JHN"
    let number: String    // "1", "2", "3" ... displayed in the chapter selector row
    let reference: String // full readable label, e.g. "Genesis 1"
}
