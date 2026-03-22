//
//  ScriptureScribeApp.swift
//  ScriptureScribe
//
//  App entry point. Wires up Firebase (once added via SPM), ThemeManager, and AuthViewModel
//  as environment objects available to every view in the app.
//

import FirebaseCore
import GoogleSignIn
import SwiftUI

@main
struct ScriptureScribeApp: App {

    @StateObject private var themeManager      = ThemeManager()
    @StateObject private var authViewModel     = AuthViewModel()
    @StateObject private var appNav            = AppNavigation()
    @StateObject private var bookmarksVM       = BookmarksViewModel()
    @StateObject private var notesVM           = NotesViewModel()
    @StateObject private var savedDevotionalsVM = SavedDevotionalsViewModel()
    @StateObject private var habitsVM          = HabitsViewModel()
    @StateObject private var subscriptionVM   = SubscriptionViewModel()
    @StateObject private var streakVM         = StreakViewModel()
    @StateObject private var walkthroughManager  = WalkthroughManager()
    @StateObject private var networkMonitor       = NetworkMonitor()

    init() {
        FirebaseApp.configure()
        // Tell Google Sign-In which OAuth client to use (reads from GoogleService-Info.plist)
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ url: URL) {
        guard let host = url.host else { return }
        let pathId = url.pathComponents.dropFirst().first ?? ""

        switch host {
        case "post":
            // Open Community tab → Insights (tab 0)
            appNav.pendingCommunityTab = 0
            appNav.selectedTab = 3
        case "gratitude":
            // Open Community tab → Gratitude (tab 1)
            appNav.pendingCommunityTab = 1
            appNav.selectedTab = 3
        case "prayer":
            // Open Community tab → Prayer (tab 2)
            appNav.pendingCommunityTab = 2
            appNav.selectedTab = 3
        case "answer", "comment":
            // Open Community tab → Daily Question (tab 3)
            appNav.pendingCommunityTab = 3
            appNav.selectedTab = 3
        case "daily":
            // Open Daily tab with specific date
            if !pathId.isEmpty {
                appNav.pendingDailyDate = pathId
            }
            appNav.selectedTab = 1
        case "verse":
            // Open Reader tab and navigate to the chapter
            if !pathId.isEmpty {
                appNav.pendingChapterId = pathId.removingPercentEncoding ?? pathId
            }
            appNav.selectedTab = 0
        default:
            break
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
            .environmentObject(themeManager)
            .environmentObject(authViewModel)
            .environmentObject(appNav)
            .environmentObject(bookmarksVM)
            .environmentObject(notesVM)
            .environmentObject(savedDevotionalsVM)
            .environmentObject(habitsVM)
            .environmentObject(subscriptionVM)
            .environmentObject(streakVM)
            .environmentObject(walkthroughManager)
            .environmentObject(networkMonitor)
            // Give the walkthrough manager access to tab navigation
            .onAppear {
                walkthroughManager.appNav = appNav
                subscriptionVM.configureForUser(authViewModel.currentUserID)
            }
            .onChange(of: authViewModel.currentUserID) { _, uid in
                subscriptionVM.configureForUser(uid)
            }
            // Required for Google Sign-In: handles the redirect after the user picks their account
            .onOpenURL { url in
                // Scripture Scribe deep links: scripturescribe://type/id
                if url.scheme == "scripturescribe" {
                    handleDeepLink(url)
                } else {
                    GIDSignIn.sharedInstance.handle(url)
                }
            }
        }
    }
}
