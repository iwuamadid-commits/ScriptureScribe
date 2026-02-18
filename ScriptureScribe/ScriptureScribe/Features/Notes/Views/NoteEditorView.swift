//
//  NoteEditorView.swift
//  ScriptureScribe
//
//  The sheet where the user types or edits a note.
//  They can also change the sticky-note color here.
//  Saving is automatic — it updates the note in NotesViewModel.
//  If the user clears all the text, the note is deleted when the sheet closes.
//

import SwiftUI

struct NoteEditorView: View {

    @ObservedObject var notesVM: NotesViewModel
    @Environment(\.dismiss) private var dismiss

    // Local copy of the note being edited
    @State private var noteText:    String = ""
    @State private var noteColorHex: String = UserNote.presetColors[0].hex
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // — Color picker row —
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(UserNote.presetColors, id: \.hex) { option in
                            colorCircle(name: option.name, hex: option.hex)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .background(Color(.systemGroupedBackground))

                Divider()

                // — Text editor — fills the rest of the screen
                ZStack(alignment: .topLeading) {
                    Color(hex: noteColorHex)

                    if noteText.isEmpty {
                        Text("Write your note here…")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    }

                    TextEditor(text: $noteText)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .focused($textFieldFocused)
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // Load the current note's content into local state
            if let note = notesVM.editingNote {
                noteText     = note.text
                noteColorHex = note.colorHex
            }
            // Open the keyboard automatically
            textFieldFocused = true
        }
    }

    // MARK: - Helpers

    private func colorCircle(name: String, hex: String) -> some View {
        let isSelected = noteColorHex == hex
        return Button {
            noteColorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(.white, lineWidth: isSelected ? 3 : 0)
                        .padding(3)
                )
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .accessibilityLabel(name)
    }

    private func saveAndDismiss() {
        guard var note = notesVM.editingNote else { dismiss(); return }
        note.text     = noteText
        note.colorHex = noteColorHex
        notesVM.updateNote(note)
        dismiss()
    }
}
