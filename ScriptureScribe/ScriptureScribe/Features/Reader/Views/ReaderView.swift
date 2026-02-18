//
//  ReaderView.swift
//  ScriptureScribe
//
//  The main Bible reading screen.
//
//  Zoom architecture:
//    • scaleEffect is applied to the entire content ZStack (text + canvas + notes)
//      so everything scales together — no snapping, always smooth.
//    • @GestureState pinchDelta updates live during the gesture; zoomScale
//      accumulates on gesture end.  The combined totalZoom drives scaleEffect.
//    • The gesture is placed with .simultaneousGesture so it fires alongside
//      PencilKit and regardless of whether the toolbar is expanded or collapsed.
//    • A double-tap resets zoom to 1×.
//
//  Bookmarks are verse-level only: long-press an individual verse to bookmark it.
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

    // MARK: - Zoom State

    @State private var zoomScale: CGFloat   = 1.0
    @GestureState private var pinchDelta: CGFloat = 1.0

    private var totalZoom: CGFloat { (zoomScale * pinchDelta).clamped(to: 0.5...4.0) }

    // MARK: - Other State

    @State private var showBookmarkPicker    = false
    @State private var showBookmarkList      = false
    @State private var showFontSizeSlider    = false
    @State private var contentHeight: CGFloat = 800
    @State private var longPressedVerseId:   String?
    @State private var longPressedVerseText: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                BookSelectorRow(vm: vm)
                Divider()

                if !vm.chapters.isEmpty {
                    ChapterSelectorRow(vm: vm, annotationVM: annotationVM)
                    Divider()
                }

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
                        case .fullWidth:  fullWidthContent(content: content)
                        case .splitView:  splitViewContent(content: content)
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
            // ── Sheets ──────────────────────────────────────────────────────
            .sheet(isPresented: $vm.showTranslationBrowser) {
                TranslationBrowserView(vm: vm)
            }
            .sheet(isPresented: $showBookmarkPicker) {
                BookmarkPickerView(
                    chapterReference: verseBookmarkReference,
                    isAlreadyBookmarked: false,       // verse-level bookmarks never "already exist"
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
            .sheet(isPresented: $showFontSizeSlider) {
                fontSizeSliderSheet
                    .presentationDetents([.height(180)])
                    .presentationDragIndicator(.visible)
            }
        }
        .task {
            await vm.loadInitialData()
            streakVM.updateStreak()
        }
    }

    // MARK: - Layout Builders

    @ViewBuilder
    private func fullWidthContent(content: BibleChapterContent) -> some View {
        scrollableReaderStack(content: content)
            .gesture(annotationVM.isAnnotating ? nil : swipeGesture)
    }

    @ViewBuilder
    private func splitViewContent(content: BibleChapterContent) -> some View {
        HStack(spacing: 0) {
            scrollableReaderStack(content: content)
                .frame(maxWidth: .infinity)
                .gesture(annotationVM.isAnnotating ? nil : swipeGesture)

            Divider()

            NotebookView(vm: annotationVM, chapterId: vm.selectedChapter?.id ?? "")
                .frame(maxWidth: .infinity)
        }
    }

    /// Scrollable ZStack: text + notes + canvas, all scaled together.
    @ViewBuilder
    private func scrollableReaderStack(content: BibleChapterContent) -> some View {
        GeometryReader { geo in
            ScrollView {
                ZStack(alignment: .topLeading) {

                    // Layer 1 — Bible text (reports its natural height)
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
                        GeometryReader { g in
                            Color.clear.preference(key: ContentHeightKey.self,
                                                   value: g.size.height)
                        }
                    )

                    // Layer 2 — Draggable note tiles
                    GeometryReader { g in
                        ForEach(notesVM.notes(for: vm.selectedChapter?.id ?? "")) { note in
                            NoteTileView(note: note, areaSize: g.size, notesVM: notesVM)
                        }
                    }
                    .frame(height: contentHeight)
                    .allowsHitTesting(!annotationVM.isAnnotating)

                    // Layer 3 — Drawing canvas
                    AnnotationCanvasView(
                        vm:            annotationVM,
                        chapterId:     vm.selectedChapter?.id ?? "",
                        contentHeight: contentHeight
                    )
                    .allowsHitTesting(annotationVM.isAnnotating)

                    // Layer 4 — Guide lines
                    if annotationVM.isAnnotating && annotationVM.showGuidelines {
                        GuideLineOverlayView(spacing: annotationVM.guideSpacing)
                            .frame(height: contentHeight)
                            .allowsHitTesting(false)
                    }
                }
                // ── Zoom: scale visually, then override frame so ScrollView
                //    knows the true (scaled) content size ───────────────────
                .frame(width: geo.size.width)
                .scaleEffect(totalZoom, anchor: .topLeading)
                .frame(width:  geo.size.width  * totalZoom,
                       height: contentHeight   * totalZoom)
            }
            .scrollDisabled(annotationVM.isAnnotating)
            .onPreferenceChange(ContentHeightKey.self) { h in if h > 0 { contentHeight = h } }
            .overlay(alignment: .topTrailing) {
                if annotationVM.isAnnotating {
                    AnnotationToolbarView(vm: annotationVM)
                }
            }
        }
        // ── Pinch-to-zoom: simultaneous so it fires alongside PencilKit ───
        // Works whether the toolbar is visible, collapsed, or hidden.
        .simultaneousGesture(pinchGesture)
        // Double-tap resets to 1×
        .onTapGesture(count: 2) {
            withAnimation(.spring(duration: 0.3)) { zoomScale = 1.0 }
        }
    }

    // MARK: - Pinch Gesture

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchDelta) { value, state, _ in state = value }
            .onEnded { value in
                let committed = (zoomScale * value).clamped(to: 0.5...4.0)
                zoomScale = committed
            }
    }

    // MARK: - Font Size Sheet

    private var fontSizeSliderSheet: some View {
        VStack(spacing: 16) {
            Text("Font Size")
                .font(.headline)
                .padding(.top, 24)

            HStack(spacing: 12) {
                Text("A").font(.system(size: 14)).foregroundStyle(.secondary)
                Slider(value: $vm.fontSize, in: 12...36, step: 1)
                Text("A").font(.system(size: 24)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)

            Text("\(Int(vm.fontSize)) pt")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        // Left: translation picker + streak (single ToolbarItem to avoid extra indent)
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 10) {
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
        }

        // Right: annotation toggle + more menu
        ToolbarItemGroup(placement: .topBarTrailing) {

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

            if !annotationVM.isAnnotating {
                Menu {

                    Section("Notes") {
                        Button {
                            if let id = vm.selectedChapter?.id { notesVM.addNote(to: id) }
                        } label: {
                            Label("Add Note", systemImage: "note.text.badge.plus")
                        }
                        .disabled(vm.chapterContent == nil)
                    }

                    Section("Bookmarks") {
                        Button { showBookmarkList = true } label: {
                            Label("All Bookmarks", systemImage: "bookmark.fill")
                        }
                    }

                    Section("Layout") {
                        Button {
                            withAnimation { annotationVM.layoutMode = .fullWidth }
                        } label: {
                            Label("Full-Width Bible",
                                  systemImage: annotationVM.layoutMode == .fullWidth
                                      ? "checkmark" : "rectangle")
                        }
                        Button {
                            withAnimation { annotationVM.layoutMode = .splitView }
                        } label: {
                            Label("Bible + Notebook",
                                  systemImage: annotationVM.layoutMode == .splitView
                                      ? "checkmark" : "rectangle.split.2x1")
                        }
                    }

                    Section("Text Alignment") {
                        Button { vm.textAlignment = "leading" } label: {
                            Label("Left",
                                  systemImage: vm.textAlignment == "leading"
                                      ? "checkmark" : "text.alignleft")
                        }
                        Button { vm.textAlignment = "center" } label: {
                            Label("Center",
                                  systemImage: vm.textAlignment == "center"
                                      ? "checkmark" : "text.aligncenter")
                        }
                        Button { vm.textAlignment = "trailing" } label: {
                            Label("Right",
                                  systemImage: vm.textAlignment == "trailing"
                                      ? "checkmark" : "text.alignright")
                        }
                    }

                    Section("Font Size") {
                        Button {
                            showFontSizeSlider = true
                        } label: {
                            Label("Adjust Font Size…", systemImage: "textformat.size")
                        }
                    }

                    Section("Font") {
                        ForEach(["System", "Georgia", "Palatino", "Baskerville"], id: \.self) { font in
                            Button { vm.fontChoice = font } label: {
                                Label(font, systemImage: vm.fontChoice == font ? "checkmark" : "")
                            }
                        }
                    }

                    Section("Book Order") {
                        Button { vm.bookSortOrder = .canonical } label: {
                            Label("Bible Order",
                                  systemImage: vm.bookSortOrder == .canonical
                                      ? "checkmark" : "list.number")
                        }
                        Button { vm.bookSortOrder = .alphabetical } label: {
                            Label("A–Z Order",
                                  systemImage: vm.bookSortOrder == .alphabetical
                                      ? "checkmark" : "textformat.abc")
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

    /// Reference label shown in the bookmark picker for the long-pressed verse.
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

// MARK: - Comparable clamp helper
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Error View

private struct ErrorView: View {
    let message: String
    let retry:   () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Try Again", action: retry).buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ReaderView()
        .environmentObject(ThemeManager())
        .environmentObject(AuthViewModel())
}
