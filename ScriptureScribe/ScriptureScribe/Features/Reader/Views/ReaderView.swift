//
//  ReaderView.swift
//  ScriptureScribe
//
//  The main Bible reading screen. Assembles all reader and annotation components:
//    • Navigation bar with translation picker, reading settings, and annotation toggle
//    • Book selector row (horizontal scroll of book names)
//    • Chapter selector row (horizontal scroll of chapter numbers)
//    • Bible text with pinch-to-zoom
//    • Transparent annotation canvas that floats on top of the text (Phase 2)
//    • Guide lines overlay for straight handwriting (Phase 2)
//    • Floating annotation toolbar (Phase 2)
//
//  Swipe left/right to move between chapters (like turning a page).
//  Tap the pencil icon in the top-right to enter annotation mode.
//

import SwiftUI

struct ReaderView: View {

    @StateObject private var vm           = ReaderViewModel()
    @StateObject private var annotationVM = AnnotationViewModel()
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

                // Main content area — text + annotation layers stacked
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
                        // Bible text + annotation layers
                        ZStack {

                            // Layer 1: Scrollable Bible text
                            BibleTextView(content: content, vm: vm)
                                .gesture(annotationVM.isAnnotating ? nil : swipeGesture)

                            // Layer 2: Guide lines (faint horizontal lines, like ruled paper)
                            if annotationVM.isAnnotating && annotationVM.showGuidelines {
                                GuideLineOverlayView(spacing: annotationVM.guideSpacing)
                            }

                            // Layer 3: Transparent drawing canvas
                            // .allowsHitTesting controls whether it blocks touches:
                            //   ON  → canvas intercepts touches for drawing (scroll blocked)
                            //   OFF → touches pass through to the scroll view below
                            AnnotationCanvasView(
                                vm: annotationVM,
                                chapterId: vm.selectedChapter?.id ?? ""
                            )
                            .allowsHitTesting(annotationVM.isAnnotating)

                            // Layer 4: Floating annotation toolbar (visible only in annotation mode)
                            if annotationVM.isAnnotating {
                                AnnotationToolbarView(vm: annotationVM)
                            }
                        }

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

                // Right: Annotation toggle + reading settings
                ToolbarItemGroup(placement: .topBarTrailing) {

                    // Pencil icon — enters / exits annotation mode
                    Button {
                        annotationVM.toggleAnnotating()
                    } label: {
                        Image(systemName: annotationVM.isAnnotating
                              ? "pencil.circle.fill"
                              : "pencil.circle")
                            .font(.title3)
                            .foregroundStyle(
                                annotationVM.isAnnotating
                                    ? themeManager.currentTheme.primary
                                    : themeManager.currentTheme.textSecondary
                            )
                    }
                    .accessibilityLabel(annotationVM.isAnnotating ? "Stop annotating" : "Start annotating")

                    // Aa menu — reading settings (hidden while annotating to reduce clutter)
                    if !annotationVM.isAnnotating {
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
    /// Disabled while annotating (canvas handles those touches instead).
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical   = abs(value.translation.height)
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
