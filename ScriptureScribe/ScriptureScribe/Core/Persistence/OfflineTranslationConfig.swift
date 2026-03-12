//
//  OfflineTranslationConfig.swift
//  ScriptureScribe
//
//  Static configuration for the three public-domain translations
//  available for offline download (KJV, WEB, ASV).
//

import Foundation

enum OfflineTranslationConfig {

    struct Info {
        let key:          String   // "KJV", "WEB", "ASV"
        let apiBibleId:   String   // API.Bible translation ID
        let displayName:  String
        let abbreviation: String
        let copyright:    String
        let firebasePath: String   // path in Firebase Storage
    }

    static let all: [Info] = [
        Info(key: "KJV",
             apiBibleId: "de4e12af7f28f599-02",
             displayName: "King James Version",
             abbreviation: "KJV",
             copyright: "Public Domain",
             firebasePath: "offline-bibles/KJV.json.gz"),
        Info(key: "WEB",
             apiBibleId: "9879dbb7cfe39e4d-01",
             displayName: "World English Bible",
             abbreviation: "WEB",
             copyright: "Public Domain",
             firebasePath: "offline-bibles/WEB.json.gz"),
        Info(key: "ASV",
             apiBibleId: "9879dbb7cfe39e4d-04",
             displayName: "American Standard Version",
             abbreviation: "ASV",
             copyright: "Public Domain",
             firebasePath: "offline-bibles/ASV.json.gz"),
    ]

    static func info(forBibleId id: String) -> Info? {
        all.first { $0.apiBibleId == id }
    }

    static func info(forKey key: String) -> Info? {
        all.first { $0.key == key }
    }

    /// All API.Bible IDs that support offline download.
    static let offlineBibleIds: Set<String> = Set(all.map(\.apiBibleId))
}
