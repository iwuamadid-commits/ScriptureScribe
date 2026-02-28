//
//  BookmarkGroup.swift
//  ScriptureScribe
//
//  A named collection the user creates to organise their bookmarks.
//  Groups are stored locally (UserDefaults) and synced to Firestore when
//  the user is signed in.
//
//  Each group has:
//    • a user-typed name  (e.g. "Prayer Verses")
//    • a ribbon color     (one of Bookmark.presetColors)
//    • an emoji icon      (any single emoji — full Apple emoji set)
//

import Foundation

struct BookmarkGroup: Identifiable, Codable {

    var id:       String
    var name:     String
    var colorHex: String   // e.g. "F5C842"
    var emoji:    String   // e.g. "📖"
    let createdAt: Date

    init(
        id:        String = UUID().uuidString,
        name:      String,
        colorHex:  String,
        emoji:     String,
        createdAt: Date = Date()
    ) {
        self.id        = id
        self.name      = name
        self.colorHex  = colorHex
        self.emoji     = emoji
        self.createdAt = createdAt
    }
}
