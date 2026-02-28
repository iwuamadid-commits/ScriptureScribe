//
//  BibleTranslation.swift
//  ScriptureScribe
//
//  Represents a single Bible translation returned by API.Bible (e.g. NIV, ESV, KJV).
//

import Foundation

struct BibleTranslation: Identifiable, Codable, Hashable {

    let id: String               // unique ID used in all API calls, e.g. "de4e12af7f28f599-02"
    let name: String             // full name, e.g. "King James Version"
    let nameLocal: String        // name in the translation's own language
    let abbreviation: String     // short code, e.g. "KJV"
    let abbreviationLocal: String
    let language: Language
    let copyright: String?       // displayed as a footer on every chapter (licensing requirement)

    struct Language: Codable, Hashable {
        let id: String           // e.g. "eng" for English, "spa" for Spanish
        let name: String         // e.g. "English"
        let nameLocal: String    // e.g. "English" or "Español"
        let scriptDirection: String? // "LTR" or "RTL" (Arabic, Hebrew read right-to-left)
    }

    /// Convenience: is this an English translation?
    var isEnglish: Bool { language.id == "eng" }

    /// Convenience: should text be displayed right-to-left?
    var isRightToLeft: Bool { language.scriptDirection == "RTL" }

    /// Clean abbreviation with any leading lowercase language-code prefix stripped.
    /// e.g. "engKJV" → "KJV",  "spaRVR60" → "RVR60",  "KJV" → "KJV"
    var displayAbbreviation: String {
        let stripped = abbreviation.drop(while: { $0.isLowercase })
        return stripped.isEmpty ? abbreviation : String(stripped)
    }
}
