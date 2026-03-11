//
//  NoteTileView.swift
//  ScriptureScribe
//
//  A draggable sticky-note tile that floats inside the scrollable Bible content.
//  Because it lives inside the same ScrollView as the text, it scrolls with the page.
//
//  Behaviour:
//    • Compact (default) — shows full note text, user-adjustable width. No buttons.
//    • Expanded (tap the text) — shows a pencil (edit) and ✕ (delete) button header.
//    • Drag anywhere on the tile to reposition it.
//    • Drag the bottom-right corner handle to resize width.
//    • Tapping anywhere outside the note collapses it (handled by parent).
//

import SwiftUI

struct NoteTileView: View {

    let note:     UserNote
    let areaSize: CGSize
    @ObservedObject var notesVM: NotesViewModel

    @GestureState private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGFloat = 0

    private var isExpanded: Bool { notesVM.expandedNoteId == note.id }

    /// The effective width, combining saved width with any in-progress resize drag.
    private var effectiveWidth: CGFloat {
        let base = CGFloat(note.noteWidth)
        return min(300, max(100, base + resizeDelta))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: effectiveWidth - 16, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            notesVM.expandedNoteId = isExpanded ? nil : note.id
                        }
                    }
            }
            .frame(width: effectiveWidth)
            .background(Color(hex: note.colorHex))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.18), radius: isExpanded ? 4 : 2, y: 2)

            // ── Resize handle (bottom-right corner) ──────────────────────────
            Image(systemName: "arrow.down.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.black.opacity(0.25))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle().inset(by: -8))
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            resizeDelta = value.translation.width
                        }
                        .onEnded { value in
                            let newWidth = min(300, max(100, CGFloat(note.noteWidth) + value.translation.width))
                            resizeDelta = 0
                            notesVM.updateWidth(id: note.id, width: Double(newWidth))
                        }
                )
        }
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
