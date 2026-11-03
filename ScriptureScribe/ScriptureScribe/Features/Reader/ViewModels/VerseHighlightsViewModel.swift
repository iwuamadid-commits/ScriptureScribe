//
//  VerseHighlightsViewModel.swift
//  ScriptureScribe
//
//  Manages the user's verse highlights.
//
//  Storage strategy mirrors BookmarksViewModel and NotesViewModel:
//  • Always saved to UserDefaults (works offline, no sign-in required).
//  • When the user is signed in, every change is also mirrored to Firestore.
//  • On sign-in, cloud highlights are fetched and merged with local ones, so a
//    highlight made on the iPhone shows up on the iPad and vice versa.
//
//  A chapter's highlights are read on every verse row while scrolling, so the
//  records are also kept in a nested dictionary (chapterId → verseNumber →
//  colorHex) for O(1) lookup. `highlights` stays the source of truth; the
//  index is rebuilt whenever it changes.
//

import Combine
import SwiftUI

@MainActor
final class VerseHighlightsViewModel: ObservableObject {

    @Published private(set) var highlights: [VerseHighlight] = []

    /// chapterId → (verseNumber → colorHex). Rebuilt from `highlights`.
    @Published private(set) var index: [String: [String: String]] = [:]

    private let storageKey = "ss_verseHighlights"
    private let firestore  = FirestoreService()

    init() {
        load()
        rebuildIndex()
    }

    // MARK: - Sync with Firestore

    /// Call when the user signs in. Uploads local-only highlights and pulls down
    /// any made on another device.
    ///
    /// Because ids are derived from the verse, the same verse highlighted on two
    /// devices collides by design. The newer `createdAt` wins and is pushed back
    /// so both ends agree, rather than letting whichever device synced last
    /// quietly keep its own color.
    func syncOnSignIn(userId: String) async {
        let cloud = (try? await firestore.fetchVerseHighlights(userId: userId)) ?? []
        var cloudById = Dictionary(cloud.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            a.createdAt >= b.createdAt ? a : b
        })

        var toUpload: [VerseHighlight] = []

        for (i, local) in highlights.enumerated() {
            guard let remote = cloudById[local.id] else {
                toUpload.append(local)          // local-only — push it up
                continue
            }
            cloudById.removeValue(forKey: local.id)
            if remote.createdAt > local.createdAt {
                highlights[i] = remote          // cloud is newer — take it
            } else if remote.colorHex != local.colorHex {
                toUpload.append(local)          // local is newer — push it up
            }
        }

        // Whatever is left in the cloud map exists only there.
        highlights.append(contentsOf: cloudById.values)

        rebuildIndex()
        save()

        for h in toUpload {
            try? await firestore.saveVerseHighlight(h, userId: userId)
        }
    }

    // MARK: - Queries

    /// The color for one verse, or nil when it isn't highlighted.
    /// Called from every verse row on screen — keep it cheap.
    func colorHex(chapterId: String, verseNumber: String) -> String? {
        index[chapterId]?[verseNumber]
    }

    /// Every highlight color used in a chapter, keyed by verse number.
    func colors(forChapter chapterId: String) -> [String: String] {
        index[chapterId] ?? [:]
    }

    /// True when any verse in the given set is already highlighted — lets the
    /// selection bubble show "Remove" only when it would do something.
    func hasAnyHighlight(chapterId: String, verseNumbers: [String]) -> Bool {
        guard let chapter = index[chapterId] else { return false }
        return verseNumbers.contains { chapter[$0] != nil }
    }

    // MARK: - Mutations

    /// Paints `verseNumbers` in `colorHex`. Re-highlighting an already-highlighted
    /// verse recolors it in place rather than stacking a second record.
    func setHighlight(
        chapterId:    String,
        verseNumbers: [String],
        colorHex:     String,
        userId:       String? = nil
    ) {
        for verseNumber in verseNumbers {
            if let existingIndex = highlights.firstIndex(where: {
                $0.chapterId == chapterId && $0.verseNumber == verseNumber
            }) {
                guard highlights[existingIndex].colorHex != colorHex else { continue }
                highlights[existingIndex].colorHex = colorHex
                let updated = highlights[existingIndex]
                if let userId {
                    Task { try? await firestore.saveVerseHighlight(updated, userId: userId) }
                }
            } else {
                let new = VerseHighlight(chapterId:   chapterId,
                                         verseNumber: verseNumber,
                                         colorHex:    colorHex)
                highlights.append(new)
                if let userId {
                    Task { try? await firestore.saveVerseHighlight(new, userId: userId) }
                }
            }
        }
        rebuildIndex()
        save()
    }

    /// Clears the highlight on each of `verseNumbers`. Verses that aren't
    /// highlighted are ignored.
    func removeHighlight(
        chapterId:    String,
        verseNumbers: [String],
        userId:       String? = nil
    ) {
        let doomed = highlights.filter {
            $0.chapterId == chapterId && verseNumbers.contains($0.verseNumber)
        }
        guard !doomed.isEmpty else { return }

        let doomedIds = Set(doomed.map(\.id))
        highlights.removeAll { doomedIds.contains($0.id) }
        if let userId {
            for id in doomedIds {
                Task { try? await firestore.deleteVerseHighlight(id: id, userId: userId) }
            }
        }
        rebuildIndex()
        save()
    }

    /// Wipes every highlight locally. Used when switching accounts — the caller
    /// is responsible for the Firestore side.
    func clearAllLocally() {
        highlights = []
        rebuildIndex()
        save()
    }

    // MARK: - Index

    private func rebuildIndex() {
        var next: [String: [String: String]] = [:]
        for h in highlights {
            next[h.chapterId, default: [:]][h.verseNumber] = h.colorHex
        }
        index = next
    }

    // MARK: - Persistence (UserDefaults)

    private func save() {
        guard let data = try? JSONEncoder().encode(highlights) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data  = UserDefaults.standard.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode([VerseHighlight].self, from: data)
        else { return }
        highlights = saved
    }
}
