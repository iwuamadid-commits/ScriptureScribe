//
//  BibleBook.swift
//  ScriptureScribe
//
//  Represents a single book of the Bible (e.g. Genesis, Psalms, John).
//

import Foundation

struct BibleBook: Identifiable, Codable, Hashable {
    let id: String          // short code used in API calls, e.g. "GEN", "JHN", "REV"
    let bibleId: String     // which translation this belongs to
    let abbreviation: String
    let name: String        // e.g. "Genesis"
    let nameLong: String    // e.g. "The First Book of Moses, called Genesis"
}
