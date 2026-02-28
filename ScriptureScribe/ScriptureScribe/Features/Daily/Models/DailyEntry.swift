//
//  DailyEntry.swift
//  ScriptureScribe
//
//  Model for one day's devotional content.
//  Sources:
//    • Firestore `dailyContent/{YYYY-MM-DD}` — AI-generated, unique every day
//    • Local DailyContent.json fallback — 30 hand-written entries used when
//      Firestore has no entry yet (e.g. no network, no API key configured)
//
//  Custom Codable init: `date` and `day` use decodeIfPresent so that the local
//  JSON (which omits those keys) still decodes cleanly.
//

import Foundation

struct DailyEntry: Codable {

    /// Calendar date for Firestore / AI-generated entries, e.g. "2026-02-23".
    /// Empty string for entries loaded from the local JSON fallback.
    var date: String = ""

    /// 1-based day index used only by the local JSON fallback.
    /// Ignored for AI-generated entries.
    var day: Int = 0

    let verseId:             String    // API.Bible verse ID, e.g. "JHN.3.16"
    let verseReference:      String    // Human-readable, e.g. "John 3:16"
    let prayer:              String
    let devotion:            String
    let affirmation:         String    // Daily faith-based affirmation
    let reflectionQuestions: [String]  // 2 per entry — shown at end of devotional

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case date, day, verseId, verseReference, prayer, devotion, affirmation, reflectionQuestions
    }

    /// Custom decoder so that entries from the local JSON (which lack `date` and `day`)
    /// still decode successfully — those keys fall back to their default values.
    init(from decoder: Decoder) throws {
        let c               = try decoder.container(keyedBy: CodingKeys.self)
        date                = try c.decodeIfPresent(String.self,   forKey: .date)                ?? ""
        day                 = try c.decodeIfPresent(Int.self,      forKey: .day)                 ?? 0
        verseId             = try c.decode(String.self,            forKey: .verseId)
        verseReference      = try c.decode(String.self,            forKey: .verseReference)
        prayer              = try c.decode(String.self,            forKey: .prayer)
        devotion            = try c.decode(String.self,            forKey: .devotion)
        affirmation         = try c.decodeIfPresent(String.self,   forKey: .affirmation)         ?? ""
        reflectionQuestions = try c.decode([String].self,          forKey: .reflectionQuestions)
    }

    /// Memberwise init used when constructing entries in code (Firestore, AI generation).
    init(date: String = "", day: Int = 0,
         verseId: String, verseReference: String,
         prayer: String, devotion: String,
         affirmation: String = "",
         reflectionQuestions: [String]) {
        self.date                = date
        self.day                 = day
        self.verseId             = verseId
        self.verseReference      = verseReference
        self.prayer              = prayer
        self.devotion            = devotion
        self.affirmation         = affirmation
        self.reflectionQuestions = reflectionQuestions
    }
}
