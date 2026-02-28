//
//  NoteTileView.swift
//  ScriptureScribe
//
//  A draggable sticky-note tile that floats inside the scrollable Bible content.
//  Because it lives inside the same ScrollView as the text, it scrolls with the page.
//
//  Behaviour:
//    • Collapsed (default) — compact bubble fitted to the note text. No buttons.
//    • Expanded (tap the text) — wider card with a pencil (edit) and ✕ (delete) button.
//    • Drag anywhere on the tile to reposition it.
//    • Tapping anywhere outside the note collapses it (handled by parent).
//

import SwiftUI

struct NoteTileView: View {

    let note:     UserNote
    let areaSize: CGSize
    @ObservedObject var notesVM: NotesViewModel

    @GestureState private var dragOffset: CGSize = .zero

    private var isExpanded: Bool { notesVM.expandedNoteId == note.id }

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
                        withAnimation(.easeOut(duration: 0.3)) {
                            notesVM.deleteNote(id: note.id)
                        }
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
            Text(note.text.isEmpty ? "Tap to expand…" : note.text)
                .font(.system(size: 13))
                .foregroundStyle(note.text.isEmpty ? Color.black.opacity(0.4) : Color.black)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: isExpanded ? 144 : 140)
                .padding(.horizontal, isExpanded ? 8 : 6)
                .padding(.vertical, isExpanded ? 8 : 4)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        notesVM.expandedNoteId = isExpanded ? nil : note.id
                    }
                }
        }
        // Expanded: fixed width for the action buttons.
        // Collapsed: hug the text content (fixedSize).
        .frame(width: isExpanded ? 160 : nil)
        .fixedSize(horizontal: !isExpanded, vertical: !isExpanded)
        .background(Color(hex: note.colorHex))
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 8 : 6))
        .shadow(color: .black.opacity(0.18), radius: isExpanded ? 4 : 2, y: 2)
        .position(
            x: note.positionX * areaSize.width  + dragOffset.width,
            y: note.positionY * areaSize.height + dragOffset.height
        )
        .gesture(
            DragGesture(minimumDistance: 8)
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
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    private func clamp(_ v: Double, lo: Double, hi: Double) -> Double {
        Swift.min(hi, Swift.max(lo, v))
    }
}
