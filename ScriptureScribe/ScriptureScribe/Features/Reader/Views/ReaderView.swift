//
//  ReaderView.swift
//  ScriptureScribe
//
//  The main Bible reading screen. Assembles all reader, annotation, note, and bookmark components:
//    • Navigation bar: translation picker, streak badge, annotation toggle, bookmark, more menu
//    • Book selector row (horizontal scroll of book names)
//    • Chapter selector row (horizontal scroll of chapter numbers)
//    • Bible text with pinch-to-zoom
//    • Annotation canvas + guide lines + toolbar (Phase 2)
//    • Draggable note tiles floating on top of the text (Phase 3)
//
//  Swipe left/right to move between chapters (like turning a page).
//

import SwiftUI

struct ReaderView: View {

    // MARK: - View Models

    @StateObject private var vm           = ReaderViewModel()
    @StateObject private var annotationVM = AnnotationViewModel()
    @StateObject private var bookmarksVM  = BookmarksViewModel()
    @StateObject private var notesVM      = NotesViewModel()
    @StateObject private var streakVM     = StreakViewModel()

    @EnvironmentObject var themeManager: ThemeManager

    // MARK: - Sheet State

    @State private var showBookmarkPicker = false
    @State private var showBookmarkList   = false

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
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading Bible…")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                        }
                    } else if vm.isLoadingContent {
                        ProgressView()
                    } else if let content = vm.chapterContent {

                        // All visible layers stacked on top of each other
                        ZStack {

                            // Layer 1: Scrollable Bible text
                            BibleTextView(content: content, vm: vm)
                                .gesture(annotationVM.isAnnotating ? nil : swipeGesture)

                            // Layer 2: Draggable note tiles
                            // GeometryReader measures the content area so notes position correctly
                            GeometryReader { geo in
                                ForEach(notesVM.notes(for: vm.selectedChapter?.id ?? "")) { note in
                                    NoteTileView(
                                        note:     note,
                                        areaSize: geo.size,
                                        notesVM:  notesVM
                                    )
                                }
                            }
                            .allowsHitTesting(!annotationVM.isAnnotating) // notes pause during drawing

                            // Layer 3: Guide lines (lined-paper effect during annotation)
                            if annotationVM.isAnnotating && annotationVM.showGuidelines {
                                GuideLineOverlayView(spacing: annotationVM.guideSpacing)
                            }

                            // Layer 4: Transparent drawing canvas
                            AnnotationCanvasView(
                                vm:        annotationVM,
                                chapterId: vm.selectedChapter?.id ?? ""
                            )
                            .allowsHitTesting(annotationVM.isAnnotating)

                            // Layer 5: Annotation toolbar (only in annotation mode)
                            if annotationVM.isAnnotating {
                                AnnotationToolbarView(vm: annotationVM)
                            }
                        }

                    } else if let error = vm.errorMessage {
                        ErrorView(message: error) {
                            Task { await vm.loadInitialData() }
                        }
                    } else {
                        Text("Select a book above to start reading.")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                }
            }
            .navigationTitle(vm.selectedChapter?.reference ?? "Scripture Scribe")
            .navigationBarTitleDisplayMode(.inline)
            .background(themeManager.currentTheme.background)
            .toolbar { toolbarContent }
            // Sheets
            .sheet(isPresented: $vm.showTranslationBrowser) {
                TranslationBrowserView(vm: vm)
            }
            .sheet(isPresented: $showBookmarkPicker) {
                BookmarkPickerView(
                    chapterReference: vm.selectedChapter?.reference ?? "",
                    isAlreadyBookmarked: isCurrentChapterBookmarked,
                    onSave: { colorHex, emoji in
                        guard
                            let chapter = vm.selectedChapter,
                            let bible   = vm.selectedTranslation,
                            let book    = vm.selectedBook
                        else { return }
                        bookmarksVM.addBookmark(
                            bibleId:  bible.id,
                            bookId:   book.id,
                            chapter:  chapter,
                            colorHex: colorHex,
                            emoji:    emoji
                        )
                    },
                    onRemove: {
                        if let id = vm.selectedChapter?.id {
                            bookmarksVM.removeBookmark(for: id)
                        }
                    }
                )
            }
            .sheet(isPresented: $showBookmarkList) {
                BookmarkListView(bookmarksVM: bookmarksVM)
            }
            .sheet(isPresented: $notesVM.showEditor) {
                NoteEditorView(notesVM: notesVM)
                    .presentationDetents([.medium, .large])
            }
        }
        .task {
            await vm.loadInitialData()
            streakVM.updateStreak()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        // Left: translation picker + streak badge
        ToolbarItemGroup(placement: .topBarLeading) {
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

            StreakBadgeView(streak: streakVM.currentStreak)
        }

        // Right: context-sensitive buttons
        ToolbarItemGroup(placement: .topBarTrailing) {

            // Annotation mode toggle (pencil icon)
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

            // Bookmark icon (filled = currently bookmarked)
            if vm.chapterContent != nil && !annotationVM.isAnnotating {
                Button {
                    showBookmarkPicker = true
                } label: {
                    Image(systemName: isCurrentChapterBookmarked
                          ? "bookmark.fill"
                          : "bookmark")
                        .foregroundStyle(
                            isCurrentChapterBookmarked
                                ? themeManager.currentTheme.primary
                                : themeManager.currentTheme.textSecondary
                        )
                }
                .accessibilityLabel(isCurrentChapterBookmarked ? "Remove bookmark" : "Bookmark this chapter")
            }

            // More menu (shown when not annotating)
            if !annotationVM.isAnnotating {
                Menu {
                    // — Notes —
                    Section("Notes") {
                        Button {
                            if let id = vm.selectedChapter?.id {
                                notesVM.addNote(to: id)
                            }
                        } label: {
                            Label("Add Note", systemImage: "note.text.badge.plus")
                        }
                        .disabled(vm.chapterContent == nil)
                    }

                    // — Bookmarks —
                    Section("Bookmarks") {
                        Button {
                            showBookmarkList = true
                        } label: {
                            Label("All Bookmarks", systemImage: "bookmark.fill")
                        }
                    }

                    // — Font Size —
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

                    // — Font Choice —
                    Section("Font") {
                        ForEach(["System", "Georgia", "Palatino", "Baskerville"], id: \.self) { font in
                            Button {
                                vm.fontChoice = font
                            } label: {
                                Label(font, systemImage: vm.fontChoice == font ? "checkmark" : "")
                            }
                        }
                    }

                    // — Book Sort Order —
                    Section("Book Order") {
                        Button {
                            vm.bookSortOrder = .canonical
                        } label: {
                            Label("Bible Order",
                                  systemImage: vm.bookSortOrder == .canonical ? "checkmark" : "list.number")
                        }
                        Button {
                            vm.bookSortOrder = .alphabetical
                        } label: {
                            Label("A–Z Order",
                                  systemImage: vm.bookSortOrder == .alphabetical ? "checkmark" : "textformat.abc")
                        }
                    }

                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
        }
    }

    // MARK: - Helpers

    private var isCurrentChapterBookmarked: Bool {
        guard let id = vm.selectedChapter?.id else { return false }
        return bookmarksVM.isBookmarked(chapterId: id)
    }

    // MARK: - Swipe to Turn Pages

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical   = abs(value.translation.height)
                guard abs(horizontal) > vertical else { return }
                if horizontal < 0 {
                    Task { await vm.goToNextChapter() }
                } else {
                    Task { await vm.goToPreviousChapter() }
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
