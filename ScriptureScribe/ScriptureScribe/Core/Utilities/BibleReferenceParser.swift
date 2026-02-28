//
//  BibleReferenceParser.swift
//  ScriptureScribe
//
//  Converts human-readable verse references like "John 3:16"
//  into API.Bible identifiers like "JHN.3.16" or "JHN.3".
//
//  Used by:
//  • VerseReferencePickerView — to fetch verse text as the user types
//  • PostCardView / CommentsView — to navigate the Reader to a tapped verse
//

import Foundation

enum BibleReferenceParser {

    // MARK: - Book Database

    /// All 66 canonical books with display name, common abbreviations, and API.Bible USFM ID.
    static let books: [(name: String, aliases: [String], apiId: String)] = [
        ("Genesis",         ["Gen", "Ge", "Gn"],                     "GEN"),
        ("Exodus",          ["Exo", "Ex", "Exod"],                   "EXO"),
        ("Leviticus",       ["Lev", "Le", "Lv"],                     "LEV"),
        ("Numbers",         ["Num", "Nu", "Nm", "Nb"],               "NUM"),
        ("Deuteronomy",     ["Deut", "Deu", "De", "Dt"],             "DEU"),
        ("Joshua",          ["Josh", "Jos", "Jsh"],                  "JOS"),
        ("Judges",          ["Judg", "Jdg", "Jg", "Jgs"],           "JDG"),
        ("Ruth",            ["Rut", "Ru"],                           "RUT"),
        ("1 Samuel",        ["1Sam", "1Sa", "1Sm", "1S"],            "1SA"),
        ("2 Samuel",        ["2Sam", "2Sa", "2Sm", "2S"],            "2SA"),
        ("1 Kings",         ["1Kgs", "1Ki", "1Kin", "1K"],           "1KI"),
        ("2 Kings",         ["2Kgs", "2Ki", "2Kin", "2K"],           "2KI"),
        ("1 Chronicles",    ["1Chr", "1Ch", "1Chron"],               "1CH"),
        ("2 Chronicles",    ["2Chr", "2Ch", "2Chron"],               "2CH"),
        ("Ezra",            ["Ezr", "Ez"],                           "EZR"),
        ("Nehemiah",        ["Neh", "Ne"],                           "NEH"),
        ("Esther",          ["Est", "Esth"],                         "EST"),
        ("Job",             ["Jb"],                                  "JOB"),
        ("Psalms",          ["Ps", "Psa", "Psalm", "Pss"],           "PSA"),
        ("Proverbs",        ["Prov", "Pro", "Prv", "Pr"],            "PRO"),
        ("Ecclesiastes",    ["Eccl", "Ecc", "Ec", "Qoh"],            "ECC"),
        ("Song of Solomon", ["Song", "SOS", "SS", "Cant"],           "SNG"),
        ("Isaiah",          ["Isa", "Is"],                           "ISA"),
        ("Jeremiah",        ["Jer", "Je", "Jr"],                     "JER"),
        ("Lamentations",    ["Lam", "La"],                           "LAM"),
        ("Ezekiel",         ["Ezek", "Eze", "Ezk"],                  "EZK"),
        ("Daniel",          ["Dan", "Da", "Dn"],                     "DAN"),
        ("Hosea",           ["Hos", "Ho"],                           "HOS"),
        ("Joel",            ["Joe", "Jl"],                           "JOL"),
        ("Amos",            ["Am"],                                   "AMO"),
        ("Obadiah",         ["Obad", "Ob"],                          "OBA"),
        ("Jonah",           ["Jon", "Jnh"],                          "JON"),
        ("Micah",           ["Mic", "Mc"],                           "MIC"),
        ("Nahum",           ["Nah", "Na"],                           "NAM"),
        ("Habakkuk",        ["Hab", "Hb"],                           "HAB"),
        ("Zephaniah",       ["Zeph", "Zep", "Zp"],                   "ZEP"),
        ("Haggai",          ["Hag", "Hg"],                           "HAG"),
        ("Zechariah",       ["Zech", "Zec", "Zc"],                   "ZEC"),
        ("Malachi",         ["Mal", "Ml"],                           "MAL"),
        ("Matthew",         ["Matt", "Mat", "Mt"],                   "MAT"),
        ("Mark",            ["Mar", "Mk", "Mrk"],                    "MRK"),
        ("Luke",            ["Luk", "Lk"],                           "LUK"),
        ("John",            ["Jhn", "Jn"],                           "JHN"),
        ("Acts",            ["Act", "Ac"],                           "ACT"),
        ("Romans",          ["Rom", "Ro", "Rm"],                     "ROM"),
        ("1 Corinthians",   ["1Cor", "1Co"],                         "1CO"),
        ("2 Corinthians",   ["2Cor", "2Co"],                         "2CO"),
        ("Galatians",       ["Gal", "Ga"],                           "GAL"),
        ("Ephesians",       ["Eph", "Ep"],                           "EPH"),
        ("Philippians",     ["Phil", "Php", "Pp"],                   "PHP"),
        ("Colossians",      ["Col", "Co"],                           "COL"),
        ("1 Thessalonians", ["1Thess", "1Th", "1Ths"],               "1TH"),
        ("2 Thessalonians", ["2Thess", "2Th", "2Ths"],               "2TH"),
        ("1 Timothy",       ["1Tim", "1Ti", "1Tm"],                  "1TI"),
        ("2 Timothy",       ["2Tim", "2Ti", "2Tm"],                  "2TI"),
        ("Titus",           ["Tit"],                                  "TIT"),
        ("Philemon",        ["Phlm", "Phm", "Pm"],                   "PHM"),
        ("Hebrews",         ["Heb", "He"],                           "HEB"),
        ("James",           ["Jas", "Jm"],                           "JAS"),
        ("1 Peter",         ["1Pet", "1Pe", "1Pt"],                  "1PE"),
        ("2 Peter",         ["2Pet", "2Pe", "2Pt"],                  "2PE"),
        ("1 John",          ["1Jhn", "1Jn", "1Jo"],                  "1JN"),
        ("2 John",          ["2Jhn", "2Jn", "2Jo"],                  "2JN"),
        ("3 John",          ["3Jhn", "3Jn", "3Jo"],                  "3JN"),
        ("Jude",            ["Jud", "Jd"],                           "JUD"),
        ("Revelation",      ["Rev", "Re", "Rv"],                     "REV"),
    ]

    // MARK: - Book Lookup

    /// Returns the API.Bible book ID for a display name or abbreviation (case-insensitive).
    static func apiBookId(for name: String) -> String? {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        for book in books {
            if book.name.lowercased() == lower { return book.apiId }
            if book.aliases.contains(where: { $0.lowercased() == lower }) { return book.apiId }
        }
        return nil
    }

    /// Returns books whose display name starts with the given prefix (case-insensitive).
    static func bookSuggestions(for prefix: String) -> [(name: String, apiId: String)] {
        let lower = prefix.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lower.isEmpty else { return [] }
        return books
            .filter { $0.name.lowercased().hasPrefix(lower) }
            .map { (name: $0.name, apiId: $0.apiId) }
    }

    // MARK: - Reference Parsing

    /// Extracts just the verse number string from a reference. "John 3:16" → "16".
    static func verseNumber(from reference: String) -> String? {
        guard let (_, _, verse) = components(of: reference) else { return nil }
        return verse
    }

    /// Parses "John 3:16" → API verse ID "JHN.3.16". Returns nil if unparseable.
    static func verseId(from reference: String) -> String? {
        guard let (bookName, chapter, verse) = components(of: reference),
              let apiId = apiBookId(for: bookName),
              let ch = chapter,
              let v = verse else { return nil }
        return "\(apiId).\(ch).\(v)"
    }

    /// Parses "John 3:16" → API chapter ID "JHN.3". Returns nil if unparseable.
    static func chapterId(from reference: String) -> String? {
        guard let (bookName, chapter, _) = components(of: reference),
              let apiId = apiBookId(for: bookName),
              let ch = chapter else { return nil }
        return "\(apiId).\(ch)"
    }

    // MARK: - Private

    /// Breaks a reference into (book, chapter, verse?) components.
    /// Works for "John 3:16", "1 John 3:16", "Song of Solomon 1:1", "Genesis 1"
    private static func components(of ref: String) -> (book: String, chapter: String?, verse: String?)? {
        let trimmed = ref.trimmingCharacters(in: .whitespaces)

        // Split on ":" → left side is "Book Chapter", right side is verse number
        let colonParts = trimmed.components(separatedBy: ":")
        let beforeColon = colonParts[0].trimmingCharacters(in: .whitespaces)
        let verseStr    = colonParts.count > 1
            ? colonParts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).first
            : nil

        // Split beforeColon at the LAST space to separate chapter number from book name.
        // "Song of Solomon 1" → book = "Song of Solomon", chapter = "1"
        // "1 John 3"          → book = "1 John",          chapter = "3"
        guard let lastSpaceIdx = beforeColon.lastIndex(of: " ") else { return nil }
        let possibleChapter = String(beforeColon[beforeColon.index(after: lastSpaceIdx)...])
        let possibleBook    = String(beforeColon[..<lastSpaceIdx])

        guard Int(possibleChapter) != nil else { return nil }
        return (possibleBook, possibleChapter, verseStr)
    }
}
