//
//  NoteTileView.swift
//  ScriptureScribe
//
//  A draggable sticky-note tile that floats inside the scrollable Bible content.
//  Because it lives inside the same ScrollView as the text, it scrolls with the page.
//  Text is always black for maximum readability. The tile width fits the note text.
//

import SwiftUI

struct NoteTileView: View {

    let note:      UserNote
    let areaSize:  CGSize
    let notesVM:   NotesViewModel

    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header bar
            HStack(spacing: 0) {
                Button {
                    notesVM.startEditing(note)
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(.leading, 8)
                        .padding(.vertical, 5)
                }
                .accessibilityLabel("Edit note")

                Spacer()

                Button(role: .destructive) {
                    notesVM.deleteNote(id: note.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(.trailing, 8)
                        .padding(.vertical, 5)
                }
                .accessibilityLabel("Delete note")
            }
            .background(Color(hex: note.colorHex).opacity(0.7))

            // Note text — always black. Width is fixed to 150 pt (compact sticky-note)
            // so the tile never looks oversized; height auto-grows with the content.
            Text(note.text.isEmpty ? "Tap ✎ to write…" : note.text)
                .font(.system(size: 13))
                .foregroundStyle(note.text.isEmpty ? Color.black.opacity(0.4) : Color.black)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(width: 150, alignment: .leading)
        }
        .background(Color(hex: note.colorHex))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .position(
            x: note.positionX * areaSize.width  + dragOffset.width,
            y: note.positionY * areaSize.height + dragOffset.height
        )
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let newX = clamp(
                        (note.positionX * areaSize.width  + value.translation.width)  / areaSize.width,
                        lo: 0.05, hi: 0.95
                    )
                    let newY = clamp(
                        (note.positionY * areaSize.height + value.translation.height) / areaSize.height,
                        lo: 0.02, hi: 0.98
                    )
                    notesVM.updatePosition(id: note.id, x: newX, y: newY)
                }
        )
    }

    private func clamp(_ v: Double, lo: Double, hi: Double) -> Double {
        Swift.min(hi, Swift.max(lo, v))
    }
}
