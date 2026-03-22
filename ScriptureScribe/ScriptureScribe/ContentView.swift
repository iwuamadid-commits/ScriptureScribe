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
    @EnvironmentObject var walkthroughManager:  WalkthroughManager
    @EnvironmentObject var networkMonitor:      NetworkMonitor

    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hasSeenOnboarding")       private var hasSeenOnboarding = false
    @AppStorage("hasCompletedWalkthrough") private var hasCompletedWalkthrough = false

    /// Tells iOS whether to render system chrome (status bar, titles) in light or dark mode.
    private var preferredColorScheme: ColorScheme {
        ["Midnight", "Forest", "Royal"].contains(themeManager.currentTheme.name) ? .dark : .light
    }

    var body: some View {
        GeometryReader { rootGeo in
            ZStack {
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
                // Offline banner — slides in just above the tab bar
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !networkMonitor.isConnected {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .font(.caption.weight(.semibold))
                            Text("You're offline. Some features may be unavailable.")
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
                // Selected tab icon uses the theme's primary colour
                .tint(themeManager.currentTheme.primary)
                // Tab bar background matches the theme's surface colour
                .toolbarBackground(themeManager.currentTheme.surface, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                // Drives status bar, title, and system icon rendering across all child views
                .preferredColorScheme(preferredColorScheme)
                // When the user signs in, sync their content from Firestore
                .onChange(of: authVM.isSignedIn) { _, signedIn in
                    if signedIn, let userId = authVM.currentUserID {
                        Task {
                            await streakVM.restoreFromCloud(userId: userId)
                            streakVM.updateStreak()
                            await bookmarksVM.syncOnSignIn(userId: userId)
                            await notesVM.syncOnSignIn(userId: userId)
                            await savedDevotionalsVM.load(userId: userId)
                            await habitsVM.syncOnSignIn(userId: userId)
                        }
                    } else if !signedIn, let userId = authVM.currentUserID {
                        // Sign-out: save streak data to cloud before leaving
                        Task { await streakVM.syncToCloud(userId: userId) }
                    }
                    // Sign-out: local data stays on device (bookmarks, notes,
                    // annotations, theme, etc.). Only account deletion clears everything.
                }
                // Save streak data to cloud when app goes to background
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background, let userId = authVM.currentUserID {
                        Task { await streakVM.syncToCloud(userId: userId) }
                    }
                }
                // Guard against edge case where app returns from background on a new calendar day
                .onAppear {
                    streakVM.updateStreak()
                    // First launch: go straight to the walkthrough welcome card
                    if !hasCompletedWalkthrough && !walkthroughManager.isActive {
                        hasSeenOnboarding = true
                        walkthroughManager.start()
                    }
                }
                // Named coordinate space for coach mark frame reporting
                .coordinateSpace(name: "walkthrough")
                // Collect frames from all .coachMark() modifiers in child views
                .onPreferenceChange(CoachMarkFrameKey.self) { frames in
                    walkthroughManager.anchorFrames = frames
                }
                // Mark walkthrough complete when manager deactivates
                .onChange(of: walkthroughManager.isActive) { _, active in
                    if !active {
                        hasCompletedWalkthrough = true
                    }
                }

                // Interactive spotlight walkthrough — two layers:
                //   1. Dim + spotlight + tooltip text  → all touches pass through
                //   2. Back / Next / Skip buttons only → small hit areas
                if walkthroughManager.isActive {
                    WalkthroughDimOverlay(manager: walkthroughManager)
                    WalkthroughControlsOverlay(manager: walkthroughManager)
                }
            }
        }
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
        .environmentObject(WalkthroughManager())
}
