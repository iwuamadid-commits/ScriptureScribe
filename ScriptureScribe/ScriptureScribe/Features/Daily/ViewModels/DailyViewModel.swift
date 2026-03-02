//
//  DailyViewModel.swift
//  ScriptureScribe
//
//  Content loading priority for any given date:
//    1. Firestore `dailyContent/{YYYY-MM-DD}` — AI-generated, shared across all users
//    2. Generate via Claude API → cache in Firestore (only for today, only if key is set)
//    3. Local DailyContent.json fallback (30 rotating entries)
//
//  The `selectedDate` property drives the calendar; it defaults to today.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class DailyViewModel: ObservableObject {

    // MARK: - Published State

    @Published var entry:         DailyEntry?  = nil
    @Published var verseText:     String?      = nil
    @Published var isLoading:     Bool         = false
    @Published var isGenerating:  Bool         = false    // true while calling Claude
    @Published var errorMessage:  String?      = nil

    /// The date whose content is currently displayed.
    @Published var selectedDate:  Date         = Date()

    // MARK: - Translation Sync

    @AppStorage("lastBibleId") private var lastBibleId: String = ""

    // MARK: - Private

    private let api          = BibleAPIService()
    private let firestore    = FirestoreService()
    private let ai           = AnthropicService()
    private var localEntries: [DailyEntry]    = []

    // MARK: - Public

    /// Called on first appearance — loads content for today.
    func load() async {
        guard !isLoading else { return }
        selectedDate = Date()
        await loadContent(for: selectedDate)
    }

    /// Load content for any calendar date. Called by WeekStrip and CalendarSheet.
    func loadContent(for date: Date) async {
        isLoading    = true
        errorMessage = nil
        entry        = nil
        verseText    = nil
        defer { isLoading = false }

        let dateString = isoDate(date)
        let isToday    = Calendar.current.isDateInToday(date)
        let isFuture   = date > Date()

        if isFuture {
            errorMessage = "No devotional yet. Check back on that day."
            return
        }

        // 1. Try Firestore cache
        if let cached = try? await firestore.fetchDailyEntry(date: dateString) {
            entry = cached
            await fetchVerseText(for: cached)
            return
        }

        // 2. Generate via AI (today only, API key required)
        if isToday, AppConfig.anthropicAPIKey != nil {
            await generateAndCache(dateString: dateString)
            return
        }

        // 3. Local JSON fallback
        loadLocalFallback(for: date)
    }

    // MARK: - Private: AI Generation

    private func generateAndCache(dateString: String) async {
        isGenerating = true
        defer { isGenerating = false }

        // Determine today's verse from the shared pool
        let verseId = AnthropicService.verseIdForDate()

        // Fetch a human-readable reference from API.Bible
        let verseReference: String
        if !lastBibleId.isEmpty,
           let verse = try? await api.fetchVerse(bibleId: lastBibleId, verseId: verseId) {
            verseReference = verse.reference
        } else {
            // Build reference from the ID as best-effort fallback
            verseReference = humanReference(from: verseId)
        }

        do {
            let generated = try await ai.generateDailyEntry(
                verseId:        verseId,
                verseReference: verseReference,
                date:           dateString
            )
            // Cache in Firestore for all subsequent users
            try? await firestore.saveDailyEntry(generated)
            entry = generated
            await fetchVerseText(for: generated)
        } catch {
            // Generation failed — fall through to local fallback
            loadLocalFallback(for: Date())
        }
    }

    // MARK: - Private: Verse Text

    private func fetchVerseText(for dailyEntry: DailyEntry) async {
        guard !lastBibleId.isEmpty else { return }
        if let verse = try? await api.fetchVerse(bibleId: lastBibleId, verseId: dailyEntry.verseId) {
            verseText = verse.text
        }
    }

    // MARK: - Private: Local Fallback

    private func loadLocalFallback(for date: Date) {
        if localEntries.isEmpty { loadLocalEntries() }
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        let index     = ((dayOfYear - 1) % 30) + 1
        if let local = localEntries.first(where: { $0.day == index }) {
            var e = local
            e.date = isoDate(date)
            entry  = e
            // Verse text will be fetched in the view's .task if needed
            Task { await fetchVerseText(for: e) }
        } else {
            errorMessage = "Couldn't load today's devotion."
        }
    }

    private func loadLocalEntries() {
        guard
            let url  = Bundle.main.url(forResource: "DailyContent", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([DailyEntry].self, from: data)
        else { return }
        localEntries = decoded
    }

    // MARK: - Helpers

    private func isoDate(_ date: Date) -> String {
        let f        = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// Builds a rough human-readable reference from an API.Bible ID like "JHN.3.16".
    private func humanReference(from id: String) -> String {
        let books: [String: String] = [
            "GEN":"Genesis","EXO":"Exodus","LEV":"Leviticus","NUM":"Numbers",
            "DEU":"Deuteronomy","JOS":"Joshua","JDG":"Judges","RUT":"Ruth",
            "1SA":"1 Samuel","2SA":"2 Samuel","1KI":"1 Kings","2KI":"2 Kings",
            "1CH":"1 Chronicles","2CH":"2 Chronicles","EZR":"Ezra","NEH":"Nehemiah",
            "EST":"Esther","JOB":"Job","PSA":"Psalm","PRO":"Proverbs","ECC":"Ecclesiastes",
            "SNG":"Song of Solomon","ISA":"Isaiah","JER":"Jeremiah","LAM":"Lamentations",
            "EZE":"Ezekiel","DAN":"Daniel","HOS":"Hosea","JOL":"Joel","AMO":"Amos",
            "OBA":"Obadiah","JON":"Jonah","MIC":"Micah","NAH":"Nahum","HAB":"Habakkuk",
            "ZEP":"Zephaniah","HAG":"Haggai","ZEC":"Zechariah","MAL":"Malachi",
            "MAT":"Matthew","MRK":"Mark","LUK":"Luke","JHN":"John","ACT":"Acts",
            "ROM":"Romans","1CO":"1 Corinthians","2CO":"2 Corinthians","GAL":"Galatians",
            "EPH":"Ephesians","PHP":"Philippians","COL":"Colossians","1TH":"1 Thessalonians",
            "2TH":"2 Thessalonians","1TI":"1 Timothy","2TI":"2 Timothy","TIT":"Titus",
            "PHM":"Philemon","HEB":"Hebrews","JAS":"James","1PE":"1 Peter","2PE":"2 Peter",
            "1JN":"1 John","2JN":"2 John","3JN":"3 John","JUD":"Jude","REV":"Revelation"
        ]
        let parts   = id.components(separatedBy: ".")
        let bookKey = parts.first ?? ""
        let chapter = parts.dropFirst().first ?? ""
        let verse   = parts.dropFirst(2).first ?? ""
        let name    = books[bookKey] ?? bookKey
        if verse.isEmpty { return "\(name) \(chapter)" }
        return "\(name) \(chapter):\(verse)"
    }
}
