//
//  ReaderView.swift
//  ScriptureScribe
//
//  The main Bible reading screen. Assembles all reader components:
//    • Navigation bar with translation picker and reading settings
//    • Book selector row (horizontal scroll of book names)
//    • Chapter selector row (horizontal scroll of chapter numbers)
//    • Bible text with pinch-to-zoom
//
//  Swipe left/right to move between chapters (like turning a page).
//

import SwiftUI

struct ReaderView: View {

    @StateObject private var vm = ReaderViewModel()
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Book selector row
                BookSelectorRow(vm: vm)

                Divider()

                // Chapter selector row (only visible once a book is selected)
                if !vm.chapters.isEmpty {
                    ChapterSelectorRow(vm: vm)
                    Divider()
                }

                // Main content area
                ZStack {
                    themeManager.currentTheme.background.ignoresSafeArea()

                    if vm.isLoadingTranslations || vm.isLoadingBooks {
                        // First launch — loading translations and books
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading Bible…")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                        }
                    } else if vm.isLoadingContent {
                        // Loading a specific chapter
                        ProgressView()
                    } else if let content = vm.chapterContent {
                        // Bible text is ready — show it
                        BibleTextView(content: content, vm: vm)
                            .gesture(swipeGesture)
                    } else if let error = vm.errorMessage {
                        // Something went wrong
                        ErrorView(message: error) {
                            Task { await vm.loadInitialData() }
                        }
                    } else {
                        // Waiting for a selection
                        Text("Select a book above to start reading.")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                }
            }
            .navigationTitle(vm.selectedChapter?.reference ?? "Scripture Scribe")
            .navigationBarTitleDisplayMode(.inline)
            .background(themeManager.currentTheme.background)
            .toolbar {
                // Left: Translation picker button
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        vm.showTranslationBrowser = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(vm.selectedTranslation?.abbreviation ?? "Bible")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(themeManager.currentTheme.primary)
                    }
                }

                // Right: Reading settings menu
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Font size controls
                        Section("Font Size") {
                            Button {
                                vm.fontSize = min(vm.fontSize + 2, 36)
                            } label: {
                                Label("Larger Text", systemImage: "textformat.size.larger")
                            }
                            Button {
                                vm.fontSize = max(vm.fontSize - 2, 12)
                            } label: {
                                Label("Smaller Text", systemImage: "textformat.size.smaller")
                            }
                        }

                        // Font choice
                        Section("Font") {
                            ForEach(["System", "Georgia", "Palatino", "Baskerville"], id: \.self) { font in
                                Button {
                                    vm.fontChoice = font
                                } label: {
                                    Label(font, systemImage: vm.fontChoice == font ? "checkmark" : "")
                                }
                            }
                        }

                        // Book sort order
                        Section("Book Order") {
                            Button {
                                vm.bookSortOrder = .canonical
                            } label: {
                                Label("Bible Order", systemImage: vm.bookSortOrder == .canonical ? "checkmark" : "list.number")
                            }
                            Button {
                                vm.bookSortOrder = .alphabetical
                            } label: {
                                Label("A–Z Order", systemImage: vm.bookSortOrder == .alphabetical ? "checkmark" : "textformat.abc")
                            }
                        }

                    } label: {
                        Image(systemName: "textformat")
                            .foregroundStyle(themeManager.currentTheme.primary)
                    }
                }
            }
            // Translation browser sheet
            .sheet(isPresented: $vm.showTranslationBrowser) {
                TranslationBrowserView(vm: vm)
            }
        }
        // Load data the first time this screen appears
        .task {
            await vm.loadInitialData()
        }
    }

    // MARK: - Swipe to Turn Pages

    /// Swipe left = next chapter, swipe right = previous chapter.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical   = abs(value.translation.height)
                // Only trigger if the swipe is more horizontal than vertical
                guard abs(horizontal) > vertical else { return }
                if horizontal < 0 {
                    Task { await vm.goToNextChapter() }     // swipe left → next
                } else {
                    Task { await vm.goToPreviousChapter() } // swipe right → previous
                }
            }
    }
}

// MARK: - Error View

private struct ErrorView: View {

    let message: String
    let retry:   () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ReaderView()
        .environmentObject(ThemeManager())
        .environmentObject(AuthViewModel())
}
