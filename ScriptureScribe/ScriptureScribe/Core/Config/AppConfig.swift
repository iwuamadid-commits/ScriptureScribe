//
//  AppConfig.swift
//  ScriptureScribe
//
//  Reads secrets from Info.plist, which is populated at build time from Secrets.xcconfig.
//  Never hardcode API keys here. See Secrets.xcconfig for setup instructions.
//

import Foundation

enum AppConfig {

    /// The API.Bible key, read from Secrets.xcconfig via Info.plist at build time.
    /// Crashes at launch with a helpful message if not configured — fail fast, fail clearly.
    static let bibleAPIKey: String = {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "BIBLE_API_KEY") as? String,
            !key.isEmpty,
            key != "your_api_key_here"
        else {
            fatalError("""

            ❌  BIBLE_API_KEY is not configured. Do these 3 things:

            1. Open Secrets.xcconfig and paste your real API.Bible key after BIBLE_API_KEY =
               (Get it at https://scripture.api.bible/profile)

            2. In Xcode: click the project name (top of navigator) → Info tab →
               Under "Configurations", set Secrets.xcconfig for both Debug and Release.

            3. In Xcode: open Info.plist → add a new row:
               Key: BIBLE_API_KEY   Type: String   Value: $(BIBLE_API_KEY)

            Then build again.
            """)
        }
        return key
    }()

    static let bibleAPIBaseURL = "https://rest.api.bible/v1"

    /// Anthropic (Claude) API key — optional. Returns nil if not configured.
    /// The app falls back to local JSON devotionals gracefully; it does NOT crash.
    static var anthropicAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String,
              !key.isEmpty,
              key != "your_claude_api_key_here"
        else { return nil }
        return key
    }

    static let anthropicBaseURL = "https://api.anthropic.com/v1/messages"
}
