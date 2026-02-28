//
//  AudioBible.swift
//  ScriptureScribe
//
//  Data models returned by the API.Bible audio endpoints.
//

import Foundation

/// A narrated version of the Bible (voice / narrator).
/// Each one has a unique ID and name — e.g. "Listener's Bible" or "ESV Audio".
struct AudioBible: Identifiable, Codable {
    let id:           String    // e.g. "105a06b6146d11e7-01"
    let name:         String    // e.g. "ESV Audio Bible (Hear the Word)"
    let nameLocal:    String?   // absent on some records
    let abbreviation: String?   // absent on some records
    let language:     AudioBibleLanguage

    struct AudioBibleLanguage: Codable {
        let id:        String?   // e.g. "eng"
        let name:      String    // e.g. "English"
        let nameLocal: String?
    }

    var isEnglish: Bool { language.name.lowercased() == "english" }
}

/// The detail object for a single audio chapter — the key field is `resourceUrl`,
/// which is a signed MP3 (or HLS) link ready to stream.
struct AudioChapterDetail: Codable {
    let id:          String
    let bibleId:     String?
    let bookId:      String?
    let number:      String?
    let reference:   String?
    let resourceUrl: String?   // signed streaming URL; nil when audio isn't available
}
