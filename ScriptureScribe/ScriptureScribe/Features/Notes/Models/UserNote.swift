//
//  UserNote.swift
//  ScriptureScribe
//
//  Represents a typed note that the user pins to a Bible chapter.
//  Notes appear as draggable sticky tiles floating on top of the text.
//
//  The position is stored as a fraction (0.0 to 1.0) of the reading area's
//  width and height, so the note lands in the right spot on any screen size.
//

import Foundation

struct UserNote: Identifiable, Codable {

    var id:        String = UUID().uuidString
    let chapterId: String   // e.g. "GEN.1" — which chapter this note belongs to
    var text:      String
    var colorHex:  String = "FFFDE7"  // soft yellow — feels like a paper sticky note
    var positionX: Double = 0.5       // 0.0 = left edge, 1.0 = right edge
    var positionY: Double = 0.3       // 0.0 = top, 1.0 = bottom
    let createdAt: Date

    // MARK: - Preset Note Colors

    static let presetColors: [(name: String, hex: String)] = [
        ("Yellow", "FFFDE7"),
        ("Blue",   "E3F2FD"),
        ("Green",  "E8F5E9"),
        ("Pink",   "FCE4EC"),
        ("Orange", "FFF3E0"),
        ("Purple", "F3E5F5"),
    ]
}
