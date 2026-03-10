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

    var isNewTestament: Bool { Self.ntBookIds.contains(id) }

    /// API.Bible IDs for all 27 New Testament books.
    static let ntBookIds: Set<String> = [
        "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO",
        "GAL", "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI",
        "TIT", "PHM", "HEB", "JAS", "1PE", "2PE", "1JN", "2JN",
        "3JN", "JUD", "REV"
    ]
}
