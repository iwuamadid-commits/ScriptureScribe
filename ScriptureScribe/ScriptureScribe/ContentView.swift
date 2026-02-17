//
//  ContentView.swift
//  ScriptureScribe
//
//  Root tab bar. Each tab will be replaced with its real view as phases complete:
//    Phase 1 → ReaderView
//    Phase 4 → SearchView
//    Phase 5 → DailyView
//    Phase 6 → CommunityView, ProfileView
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ReaderView()
                .tabItem {
                    Label("Reader", systemImage: "book.fill")
                }

            DailyPlaceholderView()
                .tabItem {
                    Label("Daily", systemImage: "sun.max.fill")
                }

            SearchPlaceholderView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            CommunityPlaceholderView()
                .tabItem {
                    Label("Community", systemImage: "person.2.fill")
                }

            ProfilePlaceholderView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle.fill")
                }
        }
    }
}

// MARK: - Placeholder Views (each replaced in its respective phase)

private struct DailyPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Daily Verse — Phase 5")
                .foregroundStyle(.secondary)
                .navigationTitle("Daily")
        }
    }
}

private struct SearchPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Search — Phase 4")
                .foregroundStyle(.secondary)
                .navigationTitle("Search")
        }
    }
}

private struct CommunityPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Community — Phase 6")
                .foregroundStyle(.secondary)
                .navigationTitle("Community")
        }
    }
}

private struct ProfilePlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Profile — Phase 6")
                .foregroundStyle(.secondary)
                .navigationTitle("Profile")
        }
    }
}

#Preview {
    ContentView()
}
