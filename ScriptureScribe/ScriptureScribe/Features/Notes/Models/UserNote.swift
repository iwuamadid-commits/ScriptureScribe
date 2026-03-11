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
    var noteWidth: Double = 160       // user-adjustable width in points (min 100, max 300)
    let createdAt: Date

    init(
        id:        String = UUID().uuidString,
        chapterId: String,
        text:      String,
        colorHex:  String = "FFFDE7",
        positionX: Double = 0.5,
        positionY: Double = 0.3,
        noteWidth: Double = 160,
        createdAt: Date
    ) {
        self.id        = id
        self.chapterId = chapterId
        self.text      = text
        self.colorHex  = colorHex
        self.positionX = positionX
        self.positionY = positionY
        self.noteWidth = noteWidth
        self.createdAt = createdAt
    }

    // Backward-compatible decoder: older saved notes won't have noteWidth
    enum CodingKeys: String, CodingKey {
        case id, chapterId, text, colorHex, positionX, positionY, noteWidth, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try  c.decode(String.self, forKey: .id)
        chapterId = try  c.decode(String.self, forKey: .chapterId)
        text      = try  c.decode(String.self, forKey: .text)
        colorHex  = (try? c.decode(String.self, forKey: .colorHex)) ?? "FFFDE7"
        positionX = try  c.decode(Double.self, forKey: .positionX)
        positionY = try  c.decode(Double.self, forKey: .positionY)
        noteWidth = (try? c.decode(Double.self, forKey: .noteWidth)) ?? 160
        createdAt = try  c.decode(Date.self,   forKey: .createdAt)
    }

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
