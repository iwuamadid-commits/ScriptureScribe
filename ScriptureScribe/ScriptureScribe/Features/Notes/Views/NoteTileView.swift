//
//  NoteTileView.swift
//  ScriptureScribe
//
//  A draggable sticky-note tile that floats inside the scrollable Bible content.
//  Because it lives inside the same ScrollView as the text, it scrolls with the page.
//
//  Behaviour:
//    • Collapsed (default) — shows only the note text. No buttons visible.
//    • Expanded (tap the text) — header appears with a pencil (edit) and ✕ (delete) button.
//    • Drag anywhere on the tile to reposition it.
//    • Text always wraps within the tile. Height grows/shrinks with the content.
//

import SwiftUI

struct NoteTileView: View {

    let note:      UserNote
    let areaSize:  CGSize
    let notesVM:   NotesViewModel

    @GestureState private var dragOffset: CGSize = .zero
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header (only visible when expanded) ─────────────────────────
            if isExpanded {
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

                    Spacer(minLength: 0)

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
            }

            // ── Note text ────────────────────────────────────────────────────
            // Tap the text to expand / collapse the header.
            // fixedSize(horizontal: false, vertical: true) means the text wraps
            // at the tile width and the tile grows taller for more content.
            Text(note.text.isEmpty ? "Tap to expand…" : note.text)
                .font(.system(size: 13))
                .foregroundStyle(note.text.isEmpty ? Color.black.opacity(0.4) : Color.black)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
        }
        .frame(width: 160)                              // fixed width so text always wraps cleanly
        .background(Color(hex: note.colorHex))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .position(
            x: note.positionX * areaSize.width  + dragOffset.width,
            y: note.positionY * areaSize.height + dragOffset.height
        )
        .gesture(
            DragGesture(minimumDistance: 8)             // 8 pt minimum so quick taps reach the text
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
