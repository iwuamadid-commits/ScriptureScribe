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

/// Holds all data the BookmarkPickerView needs when the user long-presses a verse.
/// Using .sheet(item:) with this struct guarantees the picker always opens with the
/// exact verse data that triggered the gesture — no stale-state first-load issue.
private struct VerseBookmarkData: Identifiable {
    let id           = UUID()
    let startVerseId: String
    let endVerseId:   String?   // nil = single verse; non-nil = end of range
    let verseText:    String
    let chapterRef:   String    // snapshot of chapter.reference at gesture time

    var displayReference: String {
        if let endId = endVerseId, !endId.isEmpty, endId != startVerseId {
            return "\(chapterRef): \(startVerseId)-\(endId)"
        } else {
            return "\(chapterRef): \(startVerseId)"
        }
    }
}

struct ReaderView: View {

    // MARK: - View Models

    @StateObject private var vm           = ReaderViewModel()
    @StateObject private var annotationVM = AnnotationViewModel()
    @StateObject private var streakVM     = StreakViewModel()
    @StateObject private var audioVM      = AudioPlayerViewModel()

    @EnvironmentObject var themeManager:   ThemeManager
    @EnvironmentObject var appNav:        AppNavigation
    @EnvironmentObject var bookmarksVM:   BookmarksViewModel
    @EnvironmentObject var notesVM:       NotesViewModel
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel

    // MARK: - State

    @State private var pendingVerseBookmark:     VerseBookmarkData?
    @State private var showBookmarkList          = false
    @State private var showFontSizeSlider        = false
    @State private var showSearch                = false
    @State private var showPaywall               = false
    @State private var contentHeight: CGFloat    = 800

    // ── Community verse navigation ────────────────────────────────────────────
    /// The verse number (e.g. "16") to scroll to and flash when arriving from Community.
    @State private var pendingTargetVerse:     String? = nil
    /// End of a verse range to highlight (e.g. "5" for v3-5); nil for single verse.
    @State private var pendingTargetVerseEnd:  String? = nil
    /// Y offset (in scroll-content coordinates) to jump to; cleared by ZoomScrollView.
    @State private var verseScrollOffset:      CGFloat? = nil
    /// Verse numbers currently being flashed with a highlight (cleared after ~2 s).
    @State private var highlightedVerses:      Set<String> = []

    // ── Chapter transition ────────────────────────────────────────────────────
    /// Fades the content area out when a chapter switch starts and back in when
    /// new content arrives. Avoids the double-render choppiness caused by .id().
    @State private var contentOpacity:  Double = 1.0
    /// Incremented each time a new chapter loads (without a verse target) to tell
    /// ZoomScrollView to snap to the top and reset zoom — invisible because
    /// contentOpacity is 0 during the snap.
    @State private var scrollViewReset: Int    = 0

    // MARK: - Helpers

    /// Chapter IDs that should show the annotation dot in the chapter selector.
    /// Computed here so ChapterSelectorRow doesn't need to observe annotationVM/notesVM directly.
    private var annotatedChapterIds: Set<String> {
        Set(vm.chapters.compactMap { chapter in
            (annotationVM.hasAnnotation(for: chapter.id) ||
             !notesVM.notes(for: chapter.id).isEmpty)
                ? chapter.id : nil
        })
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // In full-width mode the selectors span the whole screen.
                // In split-view mode we embed them INSIDE the Bible column
                // (via splitViewContent) so the Notebook side stays clean.
                if annotationVM.layoutMode == .fullWidth {
                    BookSelectorRow(
                        sortedBooks:    vm.sortedBooks,
                        selectedBookId: vm.selectedBook?.id,
                        bookSortOrder:  vm.bookSortOrder,
                        isLoadingBooks: vm.isLoadingBooks,
                        vm:             vm
                    )
                    Divider()
                    ChapterSelectorRow(
                        chapters:            vm.chapters,
                        selectedChapterId:   vm.selectedChapter?.id,
                        annotatedChapterIds: annotatedChapterIds,
                        vm:                  vm
                    )
                    Divider()
                    // Annotation toolbar (always visible, positioned under book/chapter selectors)
                    AnnotationToolbarView(vm: annotationVM)
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
                    } else if let content = vm.chapterContent {

                        // Views update in-place (no .id() recreation) so only ONE
                        // ZoomScrollView + AnnotationCanvasView pair ever exists.
                        // contentOpacity fades to 0 when a chapter is tapped and back
                        // to 1 when new text arrives — the in-place update is invisible.
                        Group {
                            switch annotationVM.layoutMode {
                            case .fullWidth:  fullWidthContent(content: content)
                            case .splitView:  splitViewContent(content: content)
                            }
                        }

                    } else if vm.isLoadingContent {
                        // Only reached on the very first chapter load (no previous content).
                        ProgressView()
                    } else if let error = vm.errorMessage {
                        ErrorView(message: error) {
                            Task { await vm.loadInitialData() }
                        }
                    } else {
                        Text("Select a book above to start reading.")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                }

                // Audio player bar — slides up from the bottom when active
                if audioVM.isVisible {
                    Divider()
                    AudioPlayerView(audioVM: audioVM)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(vm.selectedChapter?.reference ?? "Scripture Scribe")
            .navigationBarTitleDisplayMode(.inline)
            .background(themeManager.currentTheme.background)
            .toolbar { toolbarContent }
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // ── Sheets ──────────────────────────────────────────────────────
            .sheet(isPresented: $vm.showTranslationBrowser) {
                TranslationBrowserView(vm: vm)
            }
            .sheet(item: $pendingVerseBookmark) { data in
                BookmarkPickerView(
                    chapterReference: data.displayReference,
                    verseText:        data.verseText,
                    isAlreadyBookmarked: false,
                    onSave: { colorHex, emoji, groupId in
                        guard
                            let chapter = vm.selectedChapter,
                            let bible   = vm.selectedTranslation,
                            let book    = vm.selectedBook
                        else { return }
                        bookmarksVM.addBookmark(
                            bibleId:    bible.id,
                            bookId:     book.id,
                            chapter:    chapter,
                            verseId:    data.startVerseId,
                            verseIdEnd: data.endVerseId ?? "",
                            verseText:  data.verseText,
                            colorHex:   colorHex,
                            emoji:      emoji,
                            groupId:    groupId
                        )
                    },
                    onRemove: {
                        if let id = vm.selectedChapter?.id {
                            bookmarksVM.removeBookmark(for: id)
                        }
                    }
                )
                .environmentObject(bookmarksVM)
            }
            .sheet(isPresented: $showBookmarkList) {
                BookmarkListView(bookmarksVM: bookmarksVM)
            }
            .sheet(isPresented: $notesVM.showEditor, onDismiss: {
                notesVM.collapseExpandedNote()
            }) {
                NoteEditorView(notesVM: notesVM)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showFontSizeSlider) {
                fontSizeSliderSheet
                    .presentationDetents([.height(180)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSearch) {
                SearchView()
                    .environmentObject(themeManager)
                    .environmentObject(appNav)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
        .task {
            await vm.loadInitialData()
            streakVM.updateStreak()
            annotationVM.notesVMRef = notesVM
        }
        // When any tab sends the user here via a chapter/verse link, navigate and
        // remember the target verse so we can scroll + highlight once the content loads.
        .onChange(of: appNav.pendingChapterId) { _, newId in
            guard let id = newId else { return }
            pendingTargetVerse       = appNav.pendingVerseNumber     // save before clearing
            pendingTargetVerseEnd    = appNav.pendingVerseEndNumber  // end of range (nil for single)
            appNav.pendingVerseNumber    = nil
            appNav.pendingVerseEndNumber = nil
            appNav.pendingChapterId      = nil
            Task { await vm.navigateTo(chapterId: id) }
        }
        // Once a chapter finishes loading: fade content back in, reset scroll,
        // and (if coming from a deep link) scroll to + flash the target verse(s).
        .onChange(of: vm.chapterContent?.id) { _, _ in
            if let target = pendingTargetVerse, let content = vm.chapterContent {
                let endVerse = pendingTargetVerseEnd
                // Verse navigation — fade in, then scroll to the verse.
                pendingTargetVerse    = nil
                pendingTargetVerseEnd = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeIn(duration: 0.25)) { contentOpacity = 1 }
                }
                let verses = BibleTextView.parseVerses(from: content.textContent)
                if let idx = verses.firstIndex(where: { $0.number == target }) {
                    // Build the set of verse numbers to highlight (single or range)
                    var versesToHighlight: Set<String> = [target]
                    if let end = endVerse, let startNum = Int(target), let endNum = Int(end), endNum > startNum {
                        for n in startNum...endNum {
                            versesToHighlight.insert(String(n))
                        }
                    }
                    // Calculate the verse's Y position using NSString.boundingRect
                    // for pixel-accurate text layout (real character widths + word wrap).
                    let screenW   = UIScreen.main.bounds.width
                    let effectiveW = annotationVM.layoutMode == .splitView
                        ? floor(screenW * 0.60) : screenW
                    // 20 leading pad + 22 verse# minWidth + 6 HStack gap + 20 trailing pad
                    let textAreaW  = effectiveW - 68

                    // Build the UIFont matching the user's current font choice
                    let uiFont: UIFont = {
                        switch vm.fontChoice {
                        case "Georgia":     return UIFont(name: "Georgia", size: vm.fontSize) ?? .systemFont(ofSize: vm.fontSize)
                        case "Palatino":    return UIFont(name: "Palatino-Roman", size: vm.fontSize) ?? .systemFont(ofSize: vm.fontSize)
                        case "Baskerville": return UIFont(name: "Baskerville", size: vm.fontSize) ?? .systemFont(ofSize: vm.fontSize)
                        default:            return .systemFont(ofSize: vm.fontSize)
                        }
                    }()
                    let fontLineH = uiFont.lineHeight

                    // title2.bold() ≈ 22pt → ~28pt line height + 20 top + 16 bottom = 64
                    var estimatedY: CGFloat = 64
                    for i in 0..<idx {
                        if verses[i].number == "§" {
                            estimatedY += 34                  // section heading height
                        } else {
                            // Measure actual rendered height of the verse text
                            let boundingRect = (verses[i].text as NSString).boundingRect(
                                with: CGSize(width: textAreaW, height: .greatestFiniteMagnitude),
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: [.font: uiFont],
                                context: nil
                            )
                            let textH = ceil(boundingRect.height)
                            // SwiftUI .lineSpacing() adds extra space between lines
                            let numLines = max(1, round(textH / fontLineH))
                            let extraSpacing = max(0, numLines - 1) * vm.lineSpacing
                            let verseH = textH + extraSpacing + 8  // 8pt vertical padding
                            estimatedY += verseH
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        verseScrollOffset = estimatedY
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            highlightedVerses = versesToHighlight
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeOut(duration: 0.8)) {
                                    highlightedVerses = []
                                }
                            }
                        }
                    }
                }
            } else {
                // Normal chapter navigation — snap ZoomScrollView to top (invisible
                // because contentOpacity is 0), then fade the new text in.
                // The 0.35 s delay keeps the page invisible while ZoomScrollView
                // fires staggered scroll-to-top resets (up to 0.3 s) — this way
                // even the longest chapters (Psalm 119, 176 verses) are fully
                // laid out and scrolled to the top before the text appears.
                scrollViewReset += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeIn(duration: 0.3)) { contentOpacity = 1 }
                }
            }
        }
        // Fade content out as soon as the user taps a chapter chip or book chip,
        // so the old text is invisible while the new chapter loads in the background.
        .onChange(of: vm.selectedChapter) { _, newChapter in
            guard newChapter != nil else { return }
            // Reset overlay height so it doesn't carry over from a longer chapter
            // (invisible — contentOpacity is about to go to 0).
            contentHeight = 100
            withAnimation(.easeOut(duration: 0.2)) { contentOpacity = 0 }
        }
        .onChange(of: vm.isLoadingBooks) { _, isLoading in
            // Book switch: fade out immediately when the new book's chapters start loading.
            if isLoading, vm.chapterContent != nil {
                contentHeight = 100
                withAnimation(.easeOut(duration: 0.2)) { contentOpacity = 0 }
            }
        }
        // Load photo annotations whenever the chapter changes.
        .onChange(of: vm.selectedChapter?.id) { _, newId in
            guard let id = newId else { return }
            annotationVM.loadPhotoAnnotations(for: id)
        }
        // When new chapter text finishes loading, feed it to the audio player.
        .onChange(of: vm.chapterContent?.id) { _, _ in
            if audioVM.isVisible, let content = vm.chapterContent {
                withAnimation {
                    audioVM.openPlayer(
                        for: content.id,
                        text: content.textContent,
                        bibleId: vm.selectedTranslation?.id ?? ""
                    )
                }
            }
        }
        // Handle a photo the user just picked from the toolbar.
        .onChange(of: annotationVM.pendingPhoto) { _, image in
            guard let image, let chapterId = vm.selectedChapter?.id else { return }
            annotationVM.addPhotoAnnotation(image, for: chapterId)
            annotationVM.pendingPhoto = nil
        }
        // Lasso path captured by canvas coordinator → run hit test.
        .onChange(of: annotationVM.lassoPathPoints) { _, points in
            guard !points.isEmpty,
                  let chapterId = vm.selectedChapter?.id else { return }
            var closed = points
            if let first = points.first { closed.append(first) }
            annotationVM.lassoState.path = closed
            let screenW = UIScreen.main.bounds.width
            annotationVM.performLassoHitTest(
                areaSize:  CGSize(width: screenW, height: contentHeight),
                chapterId: chapterId,
                notes:     notesVM.notes(for: chapterId)
            )
            annotationVM.lassoPathPoints = []
        }
    }

    // MARK: - Layout Builders

    @ViewBuilder
    private func fullWidthContent(content: BibleChapterContent) -> some View {
        scrollableReaderStack(content: content)
            // Only block the swipe gesture when a drawing tool is active AND
            // finger drawing is on (otherwise finger should still turn pages).
            .gesture(annotationVM.isDrawingTool && !annotationVM.allowFingerDrawing ? swipeGesture : nil)
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

                BookSelectorRow(
                    sortedBooks:    vm.sortedBooks,
                    selectedBookId: vm.selectedBook?.id,
                    bookSortOrder:  vm.bookSortOrder,
                    isLoadingBooks: vm.isLoadingBooks,
                    vm:             vm
                )
                Divider()
                ChapterSelectorRow(
                    chapters:            vm.chapters,
                    selectedChapterId:   vm.selectedChapter?.id,
                    annotatedChapterIds: annotatedChapterIds,
                    vm:                  vm
                )
                Divider()
                // Annotation toolbar (always visible, positioned under book/chapter selectors)
                AnnotationToolbarView(vm: annotationVM)
                Divider()

                ZoomScrollView(
                    minScale:            0.5,
                    maxScale:            4.0,
                    // Only lock scrolling when drawing AND finger input is on.
                    // When finger is off, the finger should always be free to scroll.
                    isScrollingDisabled:  (annotationVM.isDrawingTool && annotationVM.allowFingerDrawing) || annotationVM.isLassoActive,
                    isContentInteractive: annotationVM.selectedTool != .hand,
                    scrollToOffset:      $verseScrollOffset,
                    resetTrigger:        scrollViewReset,
                    onDoubleTap: {
                        guard annotationVM.useDoubleTapForNote,
                              let id = vm.selectedChapter?.id else { return false }
                        notesVM.addNote(to: id)
                        return true
                    }
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
                                pendingVerseBookmark = VerseBookmarkData(
                                    startVerseId: startVerseId,
                                    endVerseId:   endVerseId,
                                    verseText:    verseText,
                                    chapterRef:   vm.selectedChapter?.reference ?? ""
                                )
                            },
                            highlightedVerses: highlightedVerses
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
                        // Allow verse long-press for bookmarks; disable only during drawing
                        .allowsHitTesting(!annotationVM.isDrawingTool)

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

                        // ── Drawing canvas (spans the full page width) ─────
                        AnnotationCanvasView(
                            vm:               annotationVM,
                            chapterId:        vm.selectedChapter?.id ?? "",
                            chapterReference: vm.selectedChapter?.reference ?? "",
                            contentHeight:    contentHeight,
                            containerWidth:   geo.size.width
                        )
                        // Canvas is hit-testable whenever a drawing tool or lasso is active.
                        // PassThroughPKCanvasView.hitTest handles finger vs pencil,
                        // so finger long-press for bookmarks still reaches BibleTextView.
                        .allowsHitTesting(annotationVM.isDrawingTool || annotationVM.isLassoActive)

                        // ── Photo annotations (above canvas so taps reach them) ──
                        let splitPhotoId = vm.selectedChapter?.id ?? ""
                        GeometryReader { _ in
                            // Invisible full-area tap target: deselects any selected photo
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(duration: 0.2)) {
                                        annotationVM.selectedPhotoId = nil
                                    }
                                }
                                .allowsHitTesting(annotationVM.selectedPhotoId != nil)

                            ForEach(annotationVM.photoAnnotations[splitPhotoId] ?? []) { photo in
                                PhotoAnnotationOverlay(
                                    photo:           photo,
                                    chapterId:       splitPhotoId,
                                    isDrawingActive: annotationVM.isDrawingTool,
                                    annotationVM:    annotationVM
                                )
                                .overlay(
                                    annotationVM.lassoState.selectedPhotoIds.contains(photo.id)
                                        ? RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                        : nil
                                )
                            }
                        }
                        .frame(height: contentHeight)
                        // Only intercept touches when NOT drawing and NOT lassoing
                        .allowsHitTesting(
                            (!annotationVM.isDrawingTool && !annotationVM.isLassoActive)
                            || annotationVM.selectedPhotoId != nil
                        )

                        // ── Note tiles (above canvas so taps reach them) ──
                        GeometryReader { g in
                            // Tap outside any note → collapse the expanded note
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        notesVM.collapseExpandedNote()
                                    }
                                }
                                .allowsHitTesting(notesVM.expandedNoteId != nil)

                            ForEach(notesVM.notes(for: vm.selectedChapter?.id ?? "")) { note in
                                NoteTileView(note: note, areaSize: g.size, notesVM: notesVM)
                                    .overlay(
                                        annotationVM.lassoState.selectedNoteIds.contains(note.id)
                                            ? RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                            : nil
                                    )
                                    .transition(.opacity)
                            }
                        }
                        .frame(height: contentHeight)
                        .allowsHitTesting(!annotationVM.isDrawingTool && !annotationVM.isLassoActive)

                        // ── Custom lasso selection overlay (only during active selection) ──
                        if annotationVM.lassoState.phase == .selected {
                            LassoOverlayView(
                                annotationVM: annotationVM,
                                notesVM:      notesVM,
                                chapterId:    vm.selectedChapter?.id ?? "",
                                areaSize:     CGSize(width: geo.size.width, height: contentHeight)
                            )
                            .frame(height: contentHeight)
                        }

                        // ── Bible-side guide lines ──────────────────────────
                        if annotationVM.showGuidelines {
                            GuideLineOverlayView(spacing: annotationVM.guideSpacing)
                                .frame(width: bibleWidth, height: contentHeight)
                                .offset(x: bibleOffset)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geo.size.width)
                }
                .onPreferenceChange(ContentHeightKey.self) { h in if h > 0 { contentHeight = h } }
                .gesture(annotationVM.isDrawingTool && !annotationVM.allowFingerDrawing ? swipeGesture : nil)
                .opacity(contentOpacity)
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
                isScrollingDisabled:  (annotationVM.isDrawingTool && annotationVM.allowFingerDrawing) || annotationVM.isLassoActive,
                isContentInteractive: true,
                scrollToOffset:      $verseScrollOffset,
                resetTrigger:        scrollViewReset,
                onDoubleTap: {
                    guard annotationVM.useDoubleTapForNote,
                          let id = vm.selectedChapter?.id else { return false }
                    notesVM.addNote(to: id)
                    return true
                }
            ) {
                ZStack(alignment: .topLeading) {

                    // Layer 1 — Bible text (reports its natural height)
                    BibleTextView(
                        content: content,
                        vm:      vm,
                        onLongPressVerse: { startVerseId, endVerseId, verseText in
                            pendingVerseBookmark = VerseBookmarkData(
                                startVerseId: startVerseId,
                                endVerseId:   endVerseId,
                                verseText:    verseText,
                                chapterRef:   vm.selectedChapter?.reference ?? ""
                            )
                        },
                        highlightedVerses: highlightedVerses
                    )
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: ContentHeightKey.self,
                                                   value: g.size.height)
                        }
                    )
                    // Allow verse long-press for bookmarks; disable only during drawing
                    .allowsHitTesting(!annotationVM.isDrawingTool)

                    // Layer 2 — Drawing canvas
                    AnnotationCanvasView(
                        vm:               annotationVM,
                        chapterId:        vm.selectedChapter?.id ?? "",
                        chapterReference: vm.selectedChapter?.reference ?? "",
                        contentHeight:    contentHeight,
                        containerWidth:   geo.size.width
                    )
                    // Canvas is hit-testable whenever a drawing tool or lasso is active.
                    // PassThroughPKCanvasView.hitTest handles finger vs pencil,
                    // so finger long-press for bookmarks still reaches BibleTextView.
                    .allowsHitTesting(annotationVM.isDrawingTool || annotationVM.isLassoActive)

                    // Layer 3 — Photo annotations (above canvas so taps reach them)
                    let photoChapterId = vm.selectedChapter?.id ?? ""
                    GeometryReader { _ in
                        // Invisible full-area tap target: deselects any selected photo
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.2)) {
                                    annotationVM.selectedPhotoId = nil
                                }
                            }
                            .allowsHitTesting(annotationVM.selectedPhotoId != nil)

                        ForEach(annotationVM.photoAnnotations[photoChapterId] ?? []) { photo in
                            PhotoAnnotationOverlay(
                                photo:           photo,
                                chapterId:       photoChapterId,
                                isDrawingActive: annotationVM.isDrawingTool,
                                annotationVM:    annotationVM
                            )
                            .overlay(
                                annotationVM.lassoState.selectedPhotoIds.contains(photo.id)
                                    ? RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                    : nil
                            )
                        }
                    }
                    .frame(height: contentHeight)
                    // Only intercept touches when NOT drawing and NOT lassoing
                    .allowsHitTesting(
                        (!annotationVM.isDrawingTool && !annotationVM.isLassoActive)
                        || annotationVM.selectedPhotoId != nil
                    )

                    // Layer 4 — Draggable note tiles (above canvas so taps reach them)
                    GeometryReader { g in
                        // Tap outside any note → collapse the expanded note
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    notesVM.collapseExpandedNote()
                                }
                            }
                            .allowsHitTesting(notesVM.expandedNoteId != nil)

                        ForEach(notesVM.notes(for: vm.selectedChapter?.id ?? "")) { note in
                            NoteTileView(note: note, areaSize: g.size, notesVM: notesVM)
                                .overlay(
                                    annotationVM.lassoState.selectedNoteIds.contains(note.id)
                                        ? RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                        : nil
                                )
                                .transition(.opacity)
                        }
                    }
                    .frame(height: contentHeight)
                    .allowsHitTesting(!annotationVM.isDrawingTool && !annotationVM.isLassoActive)

                    // Layer 4.5 — Custom lasso selection overlay (only during active selection)
                    if annotationVM.lassoState.phase == .selected {
                        LassoOverlayView(
                            annotationVM: annotationVM,
                            notesVM:      notesVM,
                            chapterId:    vm.selectedChapter?.id ?? "",
                            areaSize:     CGSize(width: geo.size.width, height: contentHeight)
                        )
                        .frame(height: contentHeight)
                    }

                    // Layer 5 — Guide lines
                    if annotationVM.showGuidelines {
                        GuideLineOverlayView(spacing: annotationVM.guideSpacing)
                            .frame(height: contentHeight)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width)
            }
            .onPreferenceChange(ContentHeightKey.self) { h in if h > 0 { contentHeight = h } }
            .opacity(contentOpacity)
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

        // Left: translation picker
        ToolbarItem(placement: .topBarLeading) {
            Button {
                vm.showTranslationBrowser = true
            } label: {
                HStack(spacing: 4) {
                    Text(vm.selectedTranslation?.displayAbbreviation ?? "Bible")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(themeManager.currentTheme.primary)
            }
        }

        // Left: streak badge (separate item so it is never clipped by the translation button)
        ToolbarItem(placement: .topBarLeading) {
            StreakBadgeView(streak: streakVM.currentStreak)
        }

        // Right: audio button + more menu
        ToolbarItemGroup(placement: .topBarTrailing) {

            // Headphones — opens / closes the audio player (premium only)
            Button {
                guard subscriptionVM.isPremium else {
                    showPaywall = true
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    if audioVM.isVisible {
                        audioVM.closePlayer()
                    } else if let content = vm.chapterContent {
                        audioVM.openPlayer(
                            for: content.id,
                            text: content.textContent,
                            bibleId: vm.selectedTranslation?.id ?? ""
                        )
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: audioVM.isVisible ? "speaker.wave.2.fill" : "speaker.wave.2")
                    if !subscriptionVM.isPremium {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(themeManager.currentTheme.primary)
            }
            .disabled(vm.chapterContent == nil)

            // Search — opens SearchView as a sheet
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(themeManager.currentTheme.primary)
            }

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

                    Section("Display") {
                        Button {
                            vm.showRedLetters.toggle()
                        } label: {
                            Label("Red Letters",
                                  systemImage: vm.showRedLetters ? "checkmark" : "")
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

// MARK: - Photo Annotation Overlay

// Carries the in-progress corner-drag state so the image resizes live while dragging.
// rawX/rawY = raw finger translation; xMult/yMult = which corner (+1 or -1).
private struct ResizeDrag {
    var rawX:  CGFloat = 0
    var rawY:  CGFloat = 0
    var xMult: CGFloat = 1
    var yMult: CGFloat = 1
    static let zero = ResizeDrag()
}

/// A fully-editable photo placed above the Bible text.
/// • Tap to select / tap again to deselect.
/// • Drag the image body to move it.
/// • Drag a corner handle to resize proportionally (live preview while dragging).
/// • Action bar (Duplicate / Delete / Style) appears above the image when selected.
private struct PhotoAnnotationOverlay: View {

    let photo:           AnnotationViewModel.PhotoAnnotation
    let chapterId:       String
    let isDrawingActive: Bool
    @ObservedObject var annotationVM: AnnotationViewModel

    // Selection is global: only one photo can be selected at a time.
    private var isSelected: Bool { annotationVM.selectedPhotoId == photo.id }
    @State private var showStyleSheet = false
    @State private var showCropView   = false

    // Live gesture deltas — each resets automatically when its gesture ends
    @GestureState private var moveDelta:  CGSize     = .zero
    @GestureState private var resizeDrag: ResizeDrag = .zero

    // Live display size: each axis grows independently in the dragged direction.
    private var liveSize: CGSize {
        guard abs(resizeDrag.rawX) > 0.1 || abs(resizeDrag.rawY) > 0.1 else { return photo.size }
        return CGSize(
            width:  max(60, photo.size.width  + resizeDrag.rawX * resizeDrag.xMult),
            height: max(60, photo.size.height + resizeDrag.rawY * resizeDrag.yMult)
        )
    }

    // How much to shift the image centre so the opposite corner stays anchored.
    // Derived analytically: centerShift = rawTranslation * (1 − mult) / 2
    private var livePositionAdjust: CGSize {
        CGSize(
            width:  resizeDrag.rawX * (1 - resizeDrag.xMult) / 2,
            height: resizeDrag.rawY * (1 - resizeDrag.yMult) / 2
        )
    }

    private var w: CGFloat { liveSize.width  }
    private var h: CGFloat { liveSize.height }

    var body: some View {
        ZStack {
            imageView

            if isSelected {
                selectionUI
            }
        }
        .rotationEffect(Angle(degrees: photo.rotation))
        .position(
            x: photo.position.x + w / 2 + moveDelta.width  + livePositionAdjust.width,
            y: photo.position.y + h / 2 + moveDelta.height + livePositionAdjust.height
        )
        .onTapGesture {
            withAnimation(.spring(duration: 0.2)) {
                annotationVM.selectedPhotoId = isSelected ? nil : photo.id
            }
        }
        .gesture(
            DragGesture()
                .updating($moveDelta) { value, state, _ in
                    guard isSelected else { return }
                    state = value.translation
                }
                .onEnded { value in
                    guard isSelected else { return }
                    annotationVM.movePhotoAnnotation(
                        id: photo.id,
                        to: CGPoint(x: photo.position.x + value.translation.width,
                                    y: photo.position.y + value.translation.height),
                        for: chapterId
                    )
                }
        )
        .sheet(isPresented: $showStyleSheet) {
            PhotoStyleSheetView(photo: photo, chapterId: chapterId, annotationVM: annotationVM)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showCropView) {
            if let img = photo.uiImage {
                CropView(originalImage: img) { croppedImage in
                    annotationVM.applyCropToPhoto(
                        id: photo.id, croppedImage: croppedImage, for: chapterId
                    )
                    showCropView = false
                } onCancel: {
                    showCropView = false
                }
            }
        }
    }

    // MARK: Image

    @ViewBuilder private var imageView: some View {
        if let img = photo.uiImage {
            Image(uiImage: img)
                .resizable()                   // stretches to fill the frame exactly — no gaps
                .frame(width: w, height: h)
                .cornerRadius(4)
                .opacity(photo.opacity)
                .overlay(borderOverlay)
                .shadow(color: .black.opacity(0.25), radius: 4)
        }
    }

    @ViewBuilder private var borderOverlay: some View {
        if photo.borderWidth > 0 {
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    Color(UIColor(hexString: photo.borderColorHex) ?? .white),
                    lineWidth: photo.borderWidth
                )
        }
    }

    // MARK: Selection UI

    @ViewBuilder private var selectionUI: some View {
        // Dashed bounding box
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.accentColor,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
            .frame(width: w + 8, height: h + 8)
            .allowsHitTesting(false)

        // Action bar — floats above the image
        actionBar
            .offset(y: -(h / 2 + 52))

        // Corner resize handles
        cornerHandle(xMult: -1, yMult: -1)   // top-left
        cornerHandle(xMult:  1, yMult: -1)   // top-right
        cornerHandle(xMult: -1, yMult:  1)   // bottom-left
        cornerHandle(xMult:  1, yMult:  1)   // bottom-right

        // Edge midpoint handles — change only width (left/right) or only height (top/bottom)
        edgeHandle(xMult:  0, yMult: -1)   // top
        edgeHandle(xMult:  0, yMult:  1)   // bottom
        edgeHandle(xMult: -1, yMult:  0)   // left
        edgeHandle(xMult:  1, yMult:  0)   // right
    }

    // MARK: Corner handle

    private func cornerHandle(xMult: CGFloat, yMult: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: 16, height: 16)
            .shadow(color: .black.opacity(0.2), radius: 2)
            .offset(x: (w / 2) * xMult, y: (h / 2) * yMult)
            .gesture(
                DragGesture()
                    // Feed raw translation + corner identity into resizeDrag every frame.
                    // liveSize and livePositionAdjust use these to resize the image
                    // directionally (the opposite corner stays anchored).
                    .updating($resizeDrag) { value, state, _ in
                        state = ResizeDrag(
                            rawX: value.translation.width,
                            rawY: value.translation.height,
                            xMult: xMult,
                            yMult: yMult
                        )
                    }
                    // On finger lift: commit the final size and the new top-left position.
                    .onEnded { value in
                        let rawX = value.translation.width
                        let rawY = value.translation.height
                        let newSize = CGSize(
                            width:  max(60, photo.size.width  + rawX * xMult),
                            height: max(60, photo.size.height + rawY * yMult)
                        )
                        // New top-left = photo.position shifted by (rawX*(1−xMult)/2, rawY*(1−yMult)/2)
                        let newPos = CGPoint(
                            x: photo.position.x + rawX * (1 - xMult) / 2,
                            y: photo.position.y + rawY * (1 - yMult) / 2
                        )
                        annotationVM.resizePhotoAnnotation(id: photo.id, size: newSize, for: chapterId)
                        annotationVM.movePhotoAnnotation(id: photo.id, to: newPos, for: chapterId)
                    }
            )
    }

    // MARK: Edge midpoint handle
    //
    // xMult / yMult describe which edge is being dragged (matching the corner-handle
    // convention), with 0 meaning "not active on that axis":
    //   top:    xMult= 0, yMult=-1   →  only rawY matters; top edge moves, bottom anchored
    //   bottom: xMult= 0, yMult= 1   →  only rawY matters; bottom edge moves, top anchored
    //   left:   xMult=-1, yMult= 0   →  only rawX matters; left edge moves, right anchored
    //   right:  xMult= 1, yMult= 0   →  only rawX matters; right edge moves, left anchored
    //
    // Because rawX=0 when yMult≠0 (and vice versa), the same liveSize /
    // livePositionAdjust math that drives corner handles works unchanged.
    //
    private func edgeHandle(xMult: CGFloat, yMult: CGFloat) -> some View {
        let isHoriz = xMult != 0              // left/right handles operate on the X axis
        let exMult  = xMult == 0 ? CGFloat(1) : xMult   // effective (rawX=0 so value irrelevant)
        let eyMult  = yMult == 0 ? CGFloat(1) : yMult   // effective (rawY=0 so value irrelevant)

        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: 14, height: 14)     // slightly smaller than corner handles
            .shadow(color: .black.opacity(0.2), radius: 2)
            .offset(x: (w / 2) * xMult, y: (h / 2) * yMult)
            .gesture(
                DragGesture()
                    .updating($resizeDrag) { value, state, _ in
                        state = ResizeDrag(
                            rawX:  isHoriz ? value.translation.width  : 0,
                            rawY:  isHoriz ? 0 : value.translation.height,
                            xMult: exMult,
                            yMult: eyMult
                        )
                    }
                    .onEnded { value in
                        let rawX = isHoriz ? value.translation.width  : 0
                        let rawY = isHoriz ? 0 : value.translation.height
                        let newSize = CGSize(
                            width:  max(60, photo.size.width  + rawX * exMult),
                            height: max(60, photo.size.height + rawY * eyMult)
                        )
                        let newPos = CGPoint(
                            x: photo.position.x + rawX * (1 - exMult) / 2,
                            y: photo.position.y + rawY * (1 - eyMult) / 2
                        )
                        annotationVM.resizePhotoAnnotation(id: photo.id, size: newSize, for: chapterId)
                        annotationVM.movePhotoAnnotation(id: photo.id, to: newPos, for: chapterId)
                    }
            )
    }

    // MARK: Action bar

    @ViewBuilder private var actionBar: some View {
        HStack(spacing: 0) {
            actionBarButton(icon: "doc.on.doc", label: "Duplicate", tint: .primary) {
                annotationVM.duplicatePhotoAnnotation(id: photo.id, for: chapterId)
                withAnimation { annotationVM.selectedPhotoId = nil }
            }
            Divider().frame(height: 28)

            actionBarButton(icon: "paintpalette", label: "Style", tint: .primary) {
                showStyleSheet = true
            }
            Divider().frame(height: 28)

            actionBarButton(icon: "crop", label: "Crop", tint: .primary) {
                showCropView = true
            }
            Divider().frame(height: 28)

            actionBarButton(icon: "trash", label: "Delete", tint: .red) {
                annotationVM.removePhotoAnnotation(id: photo.id, for: chapterId)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private func actionBarButton(icon: String, label: String, tint: Color,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(width: 72, height: 52)
            .contentShape(Rectangle())
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
        .environmentObject(AppNavigation())
}
