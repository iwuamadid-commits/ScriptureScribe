//
//  AppNavigation.swift
//  ScriptureScribe
//
//  Shared navigation state injected at the app root and observed by
//  ContentView, SearchView, and ReaderView.
//
//  When the user taps "Open Chapter" in the Handwriting search results:
//    1. SearchView sets pendingChapterId to the target chapter ID.
//    2. SearchView sets selectedTab to 0 (Reader).
//    3. ContentView switches to the Reader tab.
//    4. ReaderView sees pendingChapterId change and calls vm.navigateTo(_:).
//

import SwiftUI
import Combine

final class AppNavigation: ObservableObject {
    @Published var selectedTab:        Int     = 0     // 0=Reader 1=Daily 2=Habits 3=Community 4=Saved 5=Profile
    @Published var pendingChapterId:   String? = nil   // Reader jumps to this chapter when set
    @Published var pendingVerseNumber:    String? = nil   // Reader scrolls to + flashes this verse
    @Published var pendingVerseEndNumber: String? = nil   // End of verse range (e.g. "5" for v3-5); nil for single verse
    @Published var pendingCommunityTab:   Int?    = nil   // Community sub-tab to open (3 = Daily Question)
    @Published var pendingDailyDate:      String? = nil   // "YYYY-MM-DD" — Daily tab loads this date when set
}
