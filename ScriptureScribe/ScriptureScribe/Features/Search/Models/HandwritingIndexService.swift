//
//  HandwritingIndexService.swift
//  ScriptureScribe
//
//  Singleton that indexes handwritten annotations as searchable text.
//
//  Flow:
//    1. AnnotationCanvasView runs Vision OCR in the background whenever a
//       chapter's drawing is saved.
//    2. The recognized text + chapter reference is stored here (one entry
//       per chapter, persisted in UserDefaults).
//    3. SearchViewModel calls search(query:) to find matches; results are
//       shown in the Handwriting search tab.
//    4. Tapping a result sets AppNavigation.pendingChapterId, which causes
//       ContentView to switch to the Reader tab and jump to that chapter.
//
//  Thread safety: store() must always be called on the main thread.
//

import Foundation

// MARK: - HandwritingMatch

struct HandwritingMatch: Identifiable {
    let id        = UUID()
    let chapterId:  String   // e.g. "GEN.1"
    let reference:  String   // e.g. "Genesis 1"
    let text:       String   // full OCR'd text for that chapter
    let query:      String   // search term used, for snippet extraction

    /// A short excerpt centred on the first occurrence of `query`.
    var snippet: String {
        let lower  = text.lowercased()
        let q      = query.lowercased()
        guard let range = lower.range(of: q) else {
            return String(text.prefix(120))
        }
        let lo = text.index(range.lowerBound,
                            offsetBy: -50,
                            limitedBy: text.startIndex) ?? text.startIndex
        let hi = text.index(range.upperBound,
                            offsetBy:  60,
                            limitedBy: text.endIndex)   ?? text.endIndex
        var s = String(text[lo..<hi])
        if lo > text.startIndex { s = "…" + s }
        if hi < text.endIndex   { s = s + "…" }
        return s
    }
}

// MARK: - HandwritingIndexService

final class HandwritingIndexService {

    static let shared = HandwritingIndexService()

    private struct Entry: Codable {
        let reference: String
        let text:      String
    }

    private let storageKey = "ss_hwIndex_v1"
    private var index: [String: Entry] = [:]   // chapterId → Entry

    private init() {
        if let data  = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            index = saved
        }
    }

    // MARK: - Write

    /// Stores (or removes) the OCR result for a chapter.
    /// **Must be called on the main thread.**
    func store(text: String, reference: String, for chapterId: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            index.removeValue(forKey: chapterId)
        } else {
            index[chapterId] = Entry(reference: reference, text: trimmed)
        }
        persist()
    }

    // MARK: - Read

    /// Returns all chapters whose OCR text contains `query` (case-insensitive),
    /// sorted by chapter reference.
    func search(query: String) -> [HandwritingMatch] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return index
            .compactMap { chapterId, entry -> HandwritingMatch? in
                guard entry.text.lowercased().contains(q) else { return nil }
                return HandwritingMatch(chapterId: chapterId,
                                       reference: entry.reference,
                                       text:      entry.text,
                                       query:     query)
            }
            .sorted { $0.reference < $1.reference }
    }

    /// True when at least one chapter has been indexed.
    var hasAnyIndex: Bool { !index.isEmpty }

    // MARK: - Private

    private func persist() {
        if let data = try? JSONEncoder().encode(index) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
