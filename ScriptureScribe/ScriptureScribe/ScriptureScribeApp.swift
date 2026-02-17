//
//  ScriptureScribeApp.swift
//  ScriptureScribe
//
//  App entry point. Wires up Firebase (once added via SPM), ThemeManager, and AuthViewModel
//  as environment objects available to every view in the app.
//

import FirebaseCore
import SwiftUI

@main
struct ScriptureScribeApp: App {

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(authViewModel)
        }
    }
}
