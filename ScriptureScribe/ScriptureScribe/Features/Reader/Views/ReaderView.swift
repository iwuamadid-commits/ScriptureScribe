//
//  ReaderView.swift
//  ScriptureScribe
//
//  The main Bible reading screen. Key architecture:
//    • The ScrollView lives HERE (not inside BibleTextView).
//    • BibleTextView + AnnotationCanvasView + NoteTiles are all inside
//      the same ScrollView > ZStack so annotations scroll with the text.
//    • A PreferenceKey (ContentHeightKey) measures the text height so the
//      canvas frame matches the full scrollable content.
//    • Split-view mode shows Bible on the left, a lined notebook on the right.
//    • Long-pressing a verse opens the bookmark picker for that verse.
//

import SwiftUI

// MARK: - ContentHeightKey
// Measures the rendered height of the Bible text so the canvas can match it.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ReaderView: View {

    // MARK: - View Models

    @StateObject private var vm           = ReaderViewModel()
    @StateObject private var annotationVM = AnnotationViewModel()
    @StateObject private var bookmarksVM  = BookmarksViewModel()
    @StateObject private var notesVM      = NotesViewModel()
    @StateObject private var streakVM     = StreakViewModel()

    @EnvironmentObject var themeManager: ThemeManager

    // MARK: - State

    @State private var showBookmarkPicker     = false
    @State private var showBookmarkList       = false
    @State private var contentHeight: CGFloat = 800   // updated live by PreferenceKey
    @State private var longPressedVerseId:    String?
    @State private var longPressedVerseText:  String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Book selector row
                BookSelectorRow(vm: vm)

                Divider()

                // Chapter selector row (only visible once a book is selected)
                if !vm.chapters.isEmpty {
                    ChapterSelectorRow(vm: vm, annotationVM: annotationVM)
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

                        switch annotationVM.layoutMode {
                        case .fullWidth:
                            fullWidthContent(content: content)
                        case .splitView:
                            splitViewContent(content: content)
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
                    chapterReference: verseBookmarkReference,
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

    // MARK: - Layout Builders

    /// Full-width mode: single column — scrollable text with canvas overlay.
    @ViewBuilder
    private func fullWidthContent(content: BibleChapterContent) -> some View {
        scrollableReaderStack(content: content)
            .gesture(annotationVM.isAnnotating ? nil : swipeGesture)
    }

    /// Split-view mode: Bible on the left, lined notebook on the right.
    @ViewBuilder
    private func splitViewContent(content: BibleChapterContent) -> some View {
        HStack(spacing: 0) {
            scrollableReaderStack(content: content)
                .frame(maxWidth: .infinity)
                .gesture(annotationVM.isAnnotating ? nil : swipeGesture)

            Divider()

            NotebookView(
                vm:        annotationVM,
                chapterId: vm.selectedChapter?.id ?? ""
            )
            .frame(maxWidth: .infinity)
        }
    }

    /// The core scrollable ZStack: Bible text + floating notes + drawing canvas.
    /// ScrollView lives here so drawing annotations scroll with the text.
    @ViewBuilder
    private func scrollableReaderStack(content: BibleChapterContent) -> some View {
        ScrollView {
            ZStack(alignment: .topLeading) {

                // Layer 1 — Bible text
                // A background GeometryReader measures height and reports it via PreferenceKey.
                BibleTextView(
                    content: content,
                    vm:      vm,
                    onLongPressVerse: { verseId, verseText in
                        longPressedVerseId   = verseId
                        longPressedVerseText = verseText
                        showBookmarkPicker   = true
                    }
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key:   ContentHeightKey.self,
                            value: geo.size.height
                        )
                    }
                )

                // Layer 2 — Draggable typed note tiles
                GeometryReader { geo in
                    ForEach(notesVM.notes(for: vm.selectedChapter?.id ?? "")) { note in
                        NoteTileView(
                            note:     note,
                            areaSize: geo.size,
                            notesVM:  notesVM
                        )
                    }
                }
                .frame(height: contentHeight)
                .allowsHitTesting(!annotationVM.isAnnotating)

                // Layer 3 — PencilKit drawing canvas (same height as text)
                AnnotationCanvasView(
                    vm:            annotationVM,
                    chapterId:     vm.selectedChapter?.id ?? "",
                    contentHeight: contentHeight
                )
                .allowsHitTesting(annotationVM.isAnnotating)

                // Layer 4 — Guide lines (drawn on top of the canvas, no hit-testing)
                if annotationVM.isAnnotating && annotationVM.showGuidelines {
                    GuideLineOverlayView(spacing: annotationVM.guideSpacing)
                        .frame(height: contentHeight)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: contentHeight)
        }
        // Lock scrolling while drawing so touches go to PencilKit instead
        .scrollDisabled(annotationVM.isAnnotating)
        // Receive height updates from the text layer
        .onPreferenceChange(ContentHeightKey.self) { h in
            if h > 0 { contentHeight = h }
        }
        // Annotation toolbar floats in the top-right corner (outside the scroll)
        .overlay(alignment: .topTrailing) {
            if annotationVM.isAnnotating {
                AnnotationToolbarView(vm: annotationVM)
            }
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

        // Right: annotation toggle, bookmark, more menu
        ToolbarItemGroup(placement: .topBarTrailing) {

            // Annotation mode toggle
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

            // Bookmark button (chapter-level bookmark)
            if vm.chapterContent != nil && !annotationVM.isAnnotating {
                Button {
                    longPressedVerseId   = nil
                    longPressedVerseText = nil
                    showBookmarkPicker   = true
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
                .accessibilityLabel(isCurrentChapterBookmarked
                                    ? "Remove bookmark"
                                    : "Bookmark this chapter")
            }

            // More menu
            if !annotationVM.isAnnotating {
                Menu {

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

                    Section("Bookmarks") {
                        Button {
                            showBookmarkList = true
                        } label: {
                            Label("All Bookmarks", systemImage: "bookmark.fill")
                        }
                    }

                    Section("Layout") {
                        Button {
                            withAnimation { annotationVM.layoutMode = .fullWidth }
                        } label: {
                            Label(
                                "Full-Width Bible",
                                systemImage: annotationVM.layoutMode == .fullWidth
                                    ? "checkmark"
                                    : "rectangle"
                            )
                        }
                        Button {
                            withAnimation { annotationVM.layoutMode = .splitView }
                        } label: {
                            Label(
                                "Bible + Notebook",
                                systemImage: annotationVM.layoutMode == .splitView
                                    ? "checkmark"
                                    : "rectangle.split.2x1"
                            )
                        }
                    }

                    Section("Text Alignment") {
                        Button {
                            vm.textAlignment = "leading"
                        } label: {
                            Label("Left",
                                  systemImage: vm.textAlignment == "leading"
                                      ? "checkmark"
                                      : "text.alignleft")
                        }
                        Button {
                            vm.textAlignment = "center"
                        } label: {
                            Label("Center",
                                  systemImage: vm.textAlignment == "center"
                                      ? "checkmark"
                                      : "text.aligncenter")
                        }
                        Button {
                            vm.textAlignment = "trailing"
                        } label: {
                            Label("Right",
                                  systemImage: vm.textAlignment == "trailing"
                                      ? "checkmark"
                                      : "text.alignright")
                        }
                    }

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

                    Section("Font") {
                        ForEach(["System", "Georgia", "Palatino", "Baskerville"], id: \.self) { font in
                            Button {
                                vm.fontChoice = font
                            } label: {
                                Label(font, systemImage: vm.fontChoice == font ? "checkmark" : "")
                            }
                        }
                    }

                    Section("Book Order") {
                        Button {
                            vm.bookSortOrder = .canonical
                        } label: {
                            Label("Bible Order",
                                  systemImage: vm.bookSortOrder == .canonical
                                      ? "checkmark"
                                      : "list.number")
                        }
                        Button {
                            vm.bookSortOrder = .alphabetical
                        } label: {
                            Label("A–Z Order",
                                  systemImage: vm.bookSortOrder == .alphabetical
                                      ? "checkmark"
                                      : "textformat.abc")
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

    /// Reference label shown in the bookmark picker.
    /// Uses the verse reference when a verse was long-pressed;
    /// falls back to the whole chapter reference for the toolbar bookmark button.
    private var verseBookmarkReference: String {
        if let id = longPressedVerseId, !id.isEmpty {
            return "\(vm.selectedChapter?.reference ?? "") v\(id)"
        }
        return vm.selectedChapter?.reference ?? ""
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
