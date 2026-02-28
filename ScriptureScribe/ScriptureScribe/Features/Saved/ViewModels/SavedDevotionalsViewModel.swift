//
//  SavedDevotionalsViewModel.swift
//  ScriptureScribe
//
//  Manages the user's saved prayers and devotionals.
//  Items live in Firestore at users/{userId}/savedItems/{id}.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class SavedDevotionalsViewModel: ObservableObject {

    @Published var prayers:      [SavedDevotionalItem] = []
    @Published var devotionals:  [SavedDevotionalItem] = []
    @Published var affirmations: [SavedDevotionalItem] = []
    @Published var isLoading:    Bool                  = false

    private let firestore = FirestoreService()

    // MARK: - Load

    func load(userId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await firestore.fetchSavedItems(userId: userId)
            prayers      = all.filter { $0.type == "prayer"      }.sorted { $0.savedAt > $1.savedAt }
            devotionals  = all.filter { $0.type == "devotional"  }.sorted { $0.savedAt > $1.savedAt }
            affirmations = all.filter { $0.type == "affirmation" }.sorted { $0.savedAt > $1.savedAt }
        } catch {
            // Keep whatever is already in memory if the fetch fails
        }
    }

    // MARK: - Save

    func save(
        type:           String,    // "prayer" or "devotional"
        verseReference: String,
        content:        String,
        entryDate:      String,
        userId:         String
    ) async {
        let item = SavedDevotionalItem(
            userId:         userId,
            type:           type,
            verseReference: verseReference,
            content:        content,
            entryDate:      entryDate,
            savedAt:        Date()
        )
        // Optimistic insert so the heart fills instantly
        switch type {
        case "prayer":      prayers.insert(item, at: 0)
        case "affirmation": affirmations.insert(item, at: 0)
        default:            devotionals.insert(item, at: 0)
        }
        do {
            try await firestore.saveDevotion(item, userId: userId)
        } catch {
            // Firestore write failed — roll back the optimistic insert
            prayers      .removeAll { $0.id == item.id }
            devotionals  .removeAll { $0.id == item.id }
            affirmations .removeAll { $0.id == item.id }
        }
    }

    // MARK: - Delete

    func delete(_ item: SavedDevotionalItem, userId: String) async {
        try? await firestore.deleteSavedItem(id: item.id, userId: userId)
        prayers      .removeAll { $0.id == item.id }
        devotionals  .removeAll { $0.id == item.id }
        affirmations .removeAll { $0.id == item.id }
    }

    // MARK: - Delete by type + date (convenience for heart-button toggle)

    func delete(type: String, entryDate: String, userId: String) async {
        let items = itemsArray(for: type)
        guard let item = items.first(where: { $0.entryDate == entryDate }) else { return }
        await delete(item, userId: userId)
    }

    // MARK: - Saved State Query

    func isSaved(type: String, entryDate: String) -> Bool {
        itemsArray(for: type).contains { $0.entryDate == entryDate }
    }

    /// Returns the saved item id for a given type + date (used for deletion).
    func savedItemId(type: String, entryDate: String) -> String? {
        itemsArray(for: type).first { $0.entryDate == entryDate }?.id
    }

    private func itemsArray(for type: String) -> [SavedDevotionalItem] {
        switch type {
        case "prayer":      return prayers
        case "affirmation": return affirmations
        default:            return devotionals
        }
    }
}
