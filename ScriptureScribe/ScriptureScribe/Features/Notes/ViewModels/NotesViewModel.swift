//
//  NotesViewModel.swift
//  ScriptureScribe
//
//  Manages all typed notes across the app.
//
//  Storage strategy:
//  • Always saved to UserDefaults (works offline, no sign-in required).
//  • When the user is signed in, every add/update/delete is also mirrored to Firestore.
//  • On sign-in, Firestore notes are fetched and merged with local ones.
//

import Combine
import SwiftUI

@MainActor
final class NotesViewModel: ObservableObject {

    @Published var notes:          [UserNote] = []
    @Published var editingNote:    UserNote?
    @Published var showEditor      = false
    /// The note currently showing its edit/delete header. Only one at a time.
    @Published var expandedNoteId: String?

    private let storageKey = "scripture_scribe_notes"
    private let firestore  = FirestoreService()

    init() {
        load()
    }

    // MARK: - Sync with Firestore

    /// Call this when the user signs in. Downloads cloud notes and merges with local.
    func syncOnSignIn(userId: String) async {
        let cloudNotes = (try? await firestore.fetchNotes(userId: userId)) ?? []

        // Upload local notes that aren't in the cloud
        for local in notes {
            if !cloudNotes.contains(where: { $0.id == local.id }) {
                try? await firestore.saveNote(local, userId: userId)
            }
        }

        // Add cloud notes that aren't on this device
        for cloud in cloudNotes {
            if !notes.contains(where: { $0.id == cloud.id }) {
                notes.append(cloud)
            }
        }
        save()
    }

    // MARK: - Queries

    /// Returns all notes for a given chapter, sorted oldest-first.
    func notes(for chapterId: String) -> [UserNote] {
        notes
            .filter { $0.chapterId == chapterId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Actions

    /// Creates a new blank note for the given chapter and opens the editor.
    /// The note is NOT saved to disk yet — it only gets persisted if the user
    /// types something and saves. If they cancel or dismiss with no text, it is
    /// discarded automatically by NoteEditorView's onDisappear handler.
    func addNote(to chapterId: String) {
        let note = UserNote(chapterId: chapterId, text: "", createdAt: Date())
        notes.append(note)
        editingNote = note
        showEditor  = true
    }

    /// Opens the editor for an existing note.
    func startEditing(_ note: UserNote) {
        editingNote    = note
        showEditor     = true
        expandedNoteId = nil   // collapse the tile while editor is open
    }

    /// Collapses whichever note is currently showing its action header.
    func collapseExpandedNote() {
        expandedNoteId = nil
    }

    /// Saves changes to a note's text or color back into the array.
    func updateNote(_ updated: UserNote, userId: String? = nil) {
        guard let idx = notes.firstIndex(where: { $0.id == updated.id }) else { return }
        notes[idx] = updated
        save()
        // If text is empty after editing, remove the note entirely
        if updated.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.remove(at: idx)
            save()
            if let userId {
                Task { try? await firestore.deleteNote(id: updated.id, userId: userId) }
            }
            return
        }
        if let userId {
            Task { try? await firestore.saveNote(updated, userId: userId) }
        }
    }

    /// Updates just the position of a note (called as the user drags it).
    func updatePosition(id: String, x: Double, y: Double, userId: String? = nil) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].positionX = x
        notes[idx].positionY = y
        save()
        if let userId {
            let updated = notes[idx]
            Task { try? await firestore.saveNote(updated, userId: userId) }
        }
    }

    /// Updates the width of a note (called when the user resizes it).
    func updateWidth(id: String, width: Double) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].noteWidth = width
        save()
    }

    /// Permanently removes a note.
    func deleteNote(id: String, userId: String? = nil) {
        notes.removeAll { $0.id == id }
        save()
        if let userId {
            Task { try? await firestore.deleteNote(id: id, userId: userId) }
        }
    }

    /// Persists the current notes array to UserDefaults.
    /// Called by external code (e.g. lasso group move) after bulk position edits.
    func persistNotes() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Persistence (UserDefaults)

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data  = UserDefaults.standard.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode([UserNote].self, from: data)
        else { return }
        notes = saved
    }
}
