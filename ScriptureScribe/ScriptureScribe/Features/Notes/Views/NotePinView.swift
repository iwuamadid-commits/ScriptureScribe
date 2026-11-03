//
//  NotePinView.swift
//  ScriptureScribe
//
//  The iPhone stand-in for NoteTileView.
//
//  A typed note is authored on the iPad as a sticky tile the user drags onto
//  the page and sizes by hand (100–300pt wide). Rendered at that size on a
//  ~390pt phone screen, two or three notes bury the scripture underneath them.
//
//  So on iPhone a note collapses to a small marker at the same spot, and opens
//  into the normal editor when tapped. The position still comes from the note's
//  stored fractions, so a pin lands in the same place on the page as the tile
//  it stands for — no migration, no second source of truth.
//

import SwiftUI

struct NotePinView: View {

    let note:     UserNote
    let areaSize: CGSize
    @ObservedObject var notesVM: NotesViewModel

    /// Big enough to hit comfortably with a fingertip.
    private let diameter: CGFloat = 30

    var body: some View {
        Button {
            notesVM.startEditing(note)
        } label: {
            Image(systemName: "note.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black.opacity(0.65))
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(Color(hex: note.colorHex))
                        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                )
                .overlay(
                    Circle().stroke(.black.opacity(0.12), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .position(
            // Clamped so a pin dragged to the very edge on iPad still sits fully
            // on screen here, where the page is a different shape.
            x: min(max(note.positionX * areaSize.width,  diameter / 2),
                   max(areaSize.width  - diameter / 2, diameter / 2)),
            y: min(max(note.positionY * areaSize.height, diameter / 2),
                   max(areaSize.height - diameter / 2, diameter / 2))
        )
        .accessibilityLabel(
            note.text.isEmpty
                ? "Empty note"
                : "Note: \(note.text.prefix(40))"
        )
    }
}
