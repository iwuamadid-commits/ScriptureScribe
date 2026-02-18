//
//  NotesViewModel.swift
//  ScriptureScribe
//
//  Manages all typed notes across the app.
//  Notes are saved to UserDefaults so they survive app restarts.
//  Firebase sync will be added in Phase 6.
//

import SwiftUI

@MainActor
final class NotesViewModel: ObservableObject {

    @Published var notes: [UserNote] = []

    // The note currently being edited (nil when no editor is open)
    @Published var editingNote: UserNote?
    @Published var showEditor   = false

    private let storageKey = "scripture_scribe_notes"

    init() {
        load()
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
    func addNote(to chapterId: String) {
        let note = UserNote(chapterId: chapterId, text: "", createdAt: Date())
        notes.append(note)
        editingNote = note
        showEditor  = true
        save()
    }

    /// Opens the editor for an existing note.
    func startEditing(_ note: UserNote) {
        editingNote = note
        showEditor  = true
    }

    /// Saves changes to a note's text or color back into the array.
    func updateNote(_ updated: UserNote) {
        guard let idx = notes.firstIndex(where: { $0.id == updated.id }) else { return }
        notes[idx] = updated
        save()
        // If text is empty after editing, remove the note entirely
        if updated.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.remove(at: idx)
            save()
        }
    }

    /// Updates just the position of a note (called as the user drags it).
    func updatePosition(id: String, x: Double, y: Double) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].positionX = x
        notes[idx].positionY = y
        save()
    }

    /// Permanently removes a note.
    func deleteNote(id: String) {
        notes.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

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
