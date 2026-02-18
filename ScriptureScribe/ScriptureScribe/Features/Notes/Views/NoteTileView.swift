//
//  NoteTileView.swift
//  ScriptureScribe
//
//  A draggable sticky-note tile that floats on top of the Bible text.
//  The user can drag it anywhere on screen, tap to edit, or tap the X to delete.
//
//  Positioning: each note stores its position as a fraction (0–1) of the reading
//  area. We convert that to screen coordinates using GeometryReader in ReaderView.
//

import SwiftUI

struct NoteTileView: View {

    let note:      UserNote
    let areaSize:  CGSize           // the size of the reading area (from GeometryReader)
    let notesVM:   NotesViewModel

    // Drag state — local offset while the user is dragging, reset after they let go
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // — Header bar: color strip + edit + delete —
            HStack(spacing: 0) {
                // Edit button — opens the note editor
                Button {
                    notesVM.startEditing(note)
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .padding(.vertical, 6)
                }
                .accessibilityLabel("Edit note")

                Spacer()

                // Delete button
                Button(role: .destructive) {
                    notesVM.deleteNote(id: note.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                        .padding(.vertical, 6)
                }
                .accessibilityLabel("Delete note")
            }
            .background(Color(hex: note.colorHex).opacity(0.6))

            // — Note text body —
            Text(note.text.isEmpty ? "Tap ✎ to write a note…" : note.text)
                .font(.system(size: 13))
                .foregroundStyle(note.text.isEmpty ? .secondary : .primary)
                .lineLimit(5)
                .frame(width: 150, alignment: .leading)
                .padding(8)
        }
        .background(Color(hex: note.colorHex))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        // Position the tile's CENTER at the stored (x, y) fraction of the area
        .position(
            x: note.positionX * areaSize.width  + dragOffset.width,
            y: note.positionY * areaSize.height + dragOffset.height
        )
        // Drag to reposition
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    // Convert the final drag position to 0–1 fractions, clamped to the area
                    let newX = clamp(
                        (note.positionX * areaSize.width  + value.translation.width)  / areaSize.width,
                        min: 0.05, max: 0.95
                    )
                    let newY = clamp(
                        (note.positionY * areaSize.height + value.translation.height) / areaSize.height,
                        min: 0.05, max: 0.95
                    )
                    notesVM.updatePosition(id: note.id, x: newX, y: newY)
                }
        )
    }

    private func clamp(_ value: Double, min minVal: Double, max maxVal: Double) -> Double {
        Swift.min(maxVal, Swift.max(minVal, value))
    }
}
