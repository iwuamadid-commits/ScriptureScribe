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

    // MARK: - State

    @State private var showBookmarkPicker    = false
    @State private var showBookmarkList      = false
    @State private var showFontSizeSlider    = false
    @State private var contentHeight: CGFloat = 800
    @State private var longPressedVerseId:      String?
    @State private var longPressedVerseIdEnd:   String?
    @State private var longPressedVerseText:    String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // In full-width mode the selectors span the whole screen.
                // In split-view mode we embed them INSIDE the Bible column
                // (via splitViewContent) so the Notebook side stays clean.
                if annotationVM.layoutMode == .fullWidth {
                    BookSelectorRow(vm: vm)
                    Divider()
                    if !vm.chapters.isEmpty {
                        ChapterSelectorRow(vm: vm, annotationVM: annotationVM)
                        Divider()
                    }
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
            // Free-floating annotation toolbar: positioned absolutely over the whole
            // reading area (including selectors) so it can be dragged anywhere.
            .overlay(alignment: .topLeading) {
                if annotationVM.isAnnotating {
                    AnnotationToolbarView(vm: annotationVM)
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
                            bibleId:    bible.id,
                            bookId:     book.id,
                            chapter:    chapter,
                            verseId:    longPressedVerseId      ?? "",
                            verseIdEnd: longPressedVerseIdEnd   ?? "",
                            verseText:  longPressedVerseText    ?? "",
                            colorHex:   colorHex,
                            emoji:      emoji
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
        // ── Single continuous page ──────────────────────────────────────────────
        // The Bible text and the ruled margin are one unbroken canvas that scrolls
        // and zooms together.  There is no split: it feels like reading a printed
        // Bible and writing in the wider-than-usual margin on the side.
        // Bible text occupies 60 % of the width; the ruled margin gets the rest.
        GeometryReader { geo in
            let isLeft       = annotationVM.isLeftHanded
            let bibleWidth   = floor(geo.size.width * 0.60)
            let marginWidth  = geo.size.width - bibleWidth - 1   // -1 for separator
            let bibleOffset: CGFloat   = isLeft ? marginWidth + 1 : 0
            let marginOffset: CGFloat  = isLeft ? 0 : bibleWidth + 1

            VStack(spacing: 0) {

                BookSelectorRow(vm: vm)
                Divider()
                if !vm.chapters.isEmpty {
                    ChapterSelectorRow(vm: vm, annotationVM: annotationVM)
                    Divider()
                }

                ZoomScrollView(
                    minScale:            0.5,
                    maxScale:            4.0,
                    isScrollingDisabled: annotationVM.isAnnotating
                ) {
                    ZStack(alignment: .topLeading) {

                        // ── Background: one unbroken page ─────────────────
                        HStack(spacing: 0) {
                            themeManager.currentTheme.background
                                .frame(width: isLeft ? marginWidth : bibleWidth)
                            themeManager.currentTheme.border.opacity(0.15)
                                .frame(width: 1)
                            themeManager.currentTheme.background
                                .frame(width: isLeft ? bibleWidth : marginWidth)
                        }
                        .frame(height: contentHeight)

                        // ── Bible text ─────────────────────────────────────
                        BibleTextView(
                            content: content,
                            vm: vm,
                            onLongPressVerse: { startVerseId, endVerseId, verseText in
                                longPressedVerseId      = startVerseId
                                longPressedVerseIdEnd   = endVerseId
                                longPressedVerseText    = verseText
                                showBookmarkPicker      = true
                            }
                        )
                        .frame(width: bibleWidth)
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: ContentHeightKey.self,
                                    value: g.size.height
                                )
                            }
                        )
                        .offset(x: bibleOffset)

                        // ── Margin guide lines (always visible) ───────────
                        // These ruled lines give the margin a notebook-paper
                        // feel — always present, not just when annotating.
                        Canvas { context, size in
                            let color = themeManager.currentTheme.textSecondary.opacity(0.55)
                            var path  = Path()
                            var y     = annotationVM.guideSpacing.lineInterval
                            while y < size.height {
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                                y += annotationVM.guideSpacing.lineInterval
                            }
                            context.stroke(path, with: .color(color), lineWidth: 0.75)
                        }
                        .frame(width: marginWidth, height: contentHeight)
                        .offset(x: marginOffset)
                        .allowsHitTesting(false)

                        // ── Note tiles ─────────────────────────────────────
                        GeometryReader { g in
                            ForEach(notesVM.notes(for: vm.selectedChapter?.id ?? "")) { note in
                                NoteTileView(note: note, areaSize: g.size, notesVM: notesVM)
                            }
                        }
                        .frame(height: contentHeight)
                        .allowsHitTesting(!annotationVM.isAnnotating)

                        // ── Drawing canvas (spans the full page width) ─────
                        AnnotationCanvasView(
                            vm:             annotationVM,
                            chapterId:      vm.selectedChapter?.id ?? "",
                            contentHeight:  contentHeight,
                            containerWidth: geo.size.width
                        )
                        .allowsHitTesting(annotationVM.isAnnotating)

                        // ── Bible-side guide lines (annotation mode only) ──
                        if annotationVM.isAnnotating && annotationVM.showGuidelines {
                            GuideLineOverlayView(spacing: annotationVM.guideSpacing)
                                .frame(width: bibleWidth, height: contentHeight)
                                .offset(x: bibleOffset)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geo.size.width)
                    .onTapGesture(count: 2) {
                        if annotationVM.useDoubleTapForNote {
                            if let id = vm.selectedChapter?.id { notesVM.addNote(to: id) }
                        }
                    }
                }
                .onPreferenceChange(ContentHeightKey.self) { h in if h > 0 { contentHeight = h } }
                .gesture(annotationVM.isAnnotating ? nil : swipeGesture)
            }
        }
    }

    /// Scrollable ZStack: text + notes + canvas.
    /// ZoomScrollView wraps a UIScrollView for true focal-point pinch zoom,
    /// pan with momentum, and double-tap to reset — all native iOS behaviour.
    @ViewBuilder
    private func scrollableReaderStack(content: BibleChapterContent) -> some View {
        GeometryReader { geo in
            ZoomScrollView(
                minScale:            0.5,
                maxScale:            4.0,
                isScrollingDisabled: annotationVM.isAnnotating
            ) {
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
                        vm:             annotationVM,
                        chapterId:      vm.selectedChapter?.id ?? "",
                        contentHeight:  contentHeight,
                        containerWidth: geo.size.width
                    )
                    .allowsHitTesting(annotationVM.isAnnotating)

                    // Layer 4 — Guide lines
                    if annotationVM.isAnnotating && annotationVM.showGuidelines {
                        GuideLineOverlayView(spacing: annotationVM.guideSpacing)
                            .frame(height: contentHeight)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width)
                // Double-tap to add a note when that setting is on
                .onTapGesture(count: 2) {
                    if annotationVM.useDoubleTapForNote {
                        if let id = vm.selectedChapter?.id { notesVM.addNote(to: id) }
                    }
                    // Double-tap zoom reset is handled by ZoomScrollView natively
                }
            }
            .onPreferenceChange(ContentHeightKey.self) { h in if h > 0 { contentHeight = h } }
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

                    if annotationVM.layoutMode == .splitView {
                        Section("Margin Line Spacing") {
                            ForEach(AnnotationViewModel.GuideSpacing.allCases, id: \.self) { spacing in
                                Button {
                                    annotationVM.guideSpacing = spacing
                                } label: {
                                    Label(spacing.rawValue,
                                          systemImage: annotationVM.guideSpacing == spacing
                                              ? "checkmark" : "line.3.horizontal")
                                }
                            }
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

    /// Reference label shown in the bookmark picker for the long-pressed verse or range.
    private var verseBookmarkReference: String {
        if let startId = longPressedVerseId, !startId.isEmpty {
            if let endId = longPressedVerseIdEnd, !endId.isEmpty, endId != startId {
                return "\(vm.selectedChapter?.reference ?? "") v\(startId)-\(endId)"
            } else {
                return "\(vm.selectedChapter?.reference ?? "") v\(startId)"
            }
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
