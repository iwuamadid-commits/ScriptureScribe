//
//  PreferencesManager.swift
//  ScriptureScribe
//
//  Syncs user preferences (theme, reading settings, annotation colors, streaks, etc.)
//  to Firestore so they persist across sign-ins and devices.
//
//  On sign-in:  fetchAndApply(userId:) loads cloud prefs → writes to UserDefaults
//  On change:   save(userId:) reads UserDefaults → writes to Firestore (debounced)
//

import Combine
import SwiftUI

extension Notification.Name {
    /// Posted after cloud preferences are written to UserDefaults.
    /// ViewModels that cache UserDefaults values at init should listen for this.
    static let preferencesDidSync = Notification.Name("preferencesDidSync")
}

@MainActor
final class PreferencesManager: ObservableObject {

    private let firestore = FirestoreService()
    private var saveCancellable: AnyCancellable?
    private var saveTask: Task<Void, Never>?

    // All preference keys that should be synced per-account.
    // These match the exact UserDefaults keys used throughout the app.
    static let syncedKeys: [String] = [
        // Theme & translation
        "selectedTheme", "myVersionIds",
        // Reading preferences
        "fontSize", "lineSpacing", "fontChoice", "showRedLetters", "textAlignment",
        // Last reading position
        "lastBibleId", "lastBookId", "lastChapterId",
        // Saved annotation colors
        "ss_savedAnnotationColors_v2",
        // Annotation tool preferences
        "ss_layoutMode", "ss_eraserType", "ss_eraserSize",
        "ss_selectedTool", "ss_showGuidelines", "ss_guideSpacing",
        "ss_toolSettings", "ss_penFavSizes", "ss_hlFavSizes", "ss_eraserFavSizes",
        // Annotation toggles
        "isLeftHanded", "allowFingerDrawing", "useDoubleTapForNote",
        // Audio
        "preferredVoiceIdentifier",
        // Daily section order
        "dailySectionOrder",
        // Streaks
        "streak_currentCount", "streak_longestCount",
        "streak_lastOpenedDate", "streak_openedDatesJSON",
    ]

    // MARK: - Fetch & Apply (on sign-in)

    /// Downloads the user's preferences from Firestore and writes them to UserDefaults.
    /// Existing local values are overwritten by cloud values (cloud wins).
    func fetchAndApply(userId: String) async {
        guard let prefs = try? await firestore.fetchPreferences(userId: userId),
              !prefs.isEmpty else { return }

        let defaults = UserDefaults.standard
        for (key, value) in prefs {
            defaults.set(value, forKey: key)
        }

        // Notify ViewModels that cached UserDefaults values at init to reload
        NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
    }

    // MARK: - Save (on change, debounced)

    /// Reads current UserDefaults values for all synced keys and uploads to Firestore.
    /// Call this whenever preferences change. Internally debounced (1s) to avoid excessive writes.
    func scheduleSave(userId: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await save(userId: userId)
        }
    }

    /// Immediately saves current preferences to Firestore.
    func save(userId: String) async {
        let defaults = UserDefaults.standard
        var prefs: [String: Any] = [:]

        for key in Self.syncedKeys {
            if let value = defaults.object(forKey: key) {
                prefs[key] = value
            }
        }

        guard !prefs.isEmpty else { return }
        try? await firestore.savePreferences(prefs, userId: userId)
    }
}
