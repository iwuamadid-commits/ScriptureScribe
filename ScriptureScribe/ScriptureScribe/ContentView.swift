//
//  ContentView.swift
//  ScriptureScribe
//
//  Root tab bar. selectedTab is driven by AppNavigation so that other views
//  can programmatically switch tabs (e.g. Reader tab when tapping a verse).
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var appNav:              AppNavigation
    @EnvironmentObject var themeManager:        ThemeManager
    @EnvironmentObject var authVM:              AuthViewModel
    @EnvironmentObject var bookmarksVM:         BookmarksViewModel
    @EnvironmentObject var notesVM:             NotesViewModel
    @EnvironmentObject var savedDevotionalsVM:  SavedDevotionalsViewModel
    @EnvironmentObject var habitsVM:            HabitsViewModel
    @EnvironmentObject var streakVM:            StreakViewModel

    /// Tells iOS whether to render system chrome (status bar, titles) in light or dark mode.
    private var preferredColorScheme: ColorScheme {
        ["Midnight", "Forest", "Royal"].contains(themeManager.currentTheme.name) ? .dark : .light
    }

    var body: some View {
        TabView(selection: $appNav.selectedTab) {

            ReaderView()
                .tabItem { Label("Reader", systemImage: "book.fill") }
                .tag(0)

            DailyView()
                .tabItem { Label("Daily", systemImage: "sun.max.fill") }
                .tag(1)

            HabitsView()
                .tabItem { Label("Habits", systemImage: "checkmark.circle.fill") }
                .tag(2)

            FeedView()
                .tabItem { Label("Community", systemImage: "person.2.fill") }
                .tag(3)

            SavedView()
                .tabItem { Label("Library", systemImage: "bookmark.fill") }
                .tag(4)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.circle.fill") }
                .tag(5)
        }
        // Selected tab icon uses the theme's primary colour
        .tint(themeManager.currentTheme.primary)
        // Tab bar background matches the theme's surface colour
        .toolbarBackground(themeManager.currentTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        // Drives status bar, title, and system icon rendering across all child views
        .preferredColorScheme(preferredColorScheme)
        // When the user signs in, sync local data to Firestore
        .onChange(of: authVM.isSignedIn) { _, signedIn in
            guard signedIn, let userId = authVM.currentUserID else { return }
            Task {
                await bookmarksVM.syncOnSignIn(userId: userId)
                await notesVM.syncOnSignIn(userId: userId)
                await savedDevotionalsVM.load(userId: userId)
                await habitsVM.syncOnSignIn(userId: userId)
            }
        }
        // Guard against edge case where app returns from background on a new calendar day
        .onAppear { streakVM.updateStreak() }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppNavigation())
        .environmentObject(ThemeManager())
        .environmentObject(AuthViewModel())
        .environmentObject(BookmarksViewModel())
        .environmentObject(NotesViewModel())
        .environmentObject(SavedDevotionalsViewModel())
        .environmentObject(HabitsViewModel())
        .environmentObject(StreakViewModel())
}
