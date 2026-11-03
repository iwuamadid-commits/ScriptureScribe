//
//  BibleTextView.swift
//  ScriptureScribe
//
//  Displays Bible text verse-by-verse so each verse can be long-pressed to bookmark.
//  This view has NO internal ScrollView — the parent ReaderView owns the scroll,
//  which allows the annotation canvas to scroll with the text.
//

import Combine
import SwiftUI

// MARK: - Preference key (locates the first selected verse for bubble positioning)

private struct FirstSelectedVerseAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    /// Keeps whichever anchor was reported first (smallest ForEach index = topmost verse).
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - BibleTextView

struct BibleTextView: View {

    let content:            BibleChapterContent
    @ObservedObject var vm: ReaderViewModel
    let onLongPressVerse:   ([String], String) -> Void  // (verseNumbers, combinedText)
    /// Called when user taps a verse while the audio player is active.
    /// Passes the verse number so the caller can seek audio to it.
    /// Nil when the player is not visible — tapping does nothing in that case.
    var onTapVerse:         ((String) -> Void)? = nil
    /// Verse numbers to briefly highlight (e.g. {"3","4","5"}). Empty when no navigation target.
    var highlightedVerses:  Set<String> = []
    /// The verse currently being narrated by the audio player ("" when not playing).
    var playingVerse:       String      = ""
    /// True while a drawing tool is selected. Switches off verse taps so strokes
    /// aren't intercepted, while leaving the Prev/Next footer tappable by finger.
    var isDrawingToolActive: Bool       = false
    /// Shared with ReaderView so footer positions escape the scroll view's
    /// UIHostingController, which preferences cannot cross.
    @ObservedObject var footerMetrics: ReaderFooterMetrics
    /// Owns the user's verse highlights.
    ///
    /// Handed in explicitly rather than read from the environment: this view
    /// renders inside ZoomScrollView's UIHostingController, and an explicit
    /// hand-off is guaranteed to arrive where environment propagation across
    /// that boundary is not something to rely on.
    @ObservedObject var highlightsVM: VerseHighlightsViewModel
    /// Signed-in user id, or nil when signed out. Highlighting works either way;
    /// this only decides whether the change is mirrored to Firestore.
    var highlightUserId: String? = nil
    /// True when the user may use all 8 highlight colors rather than the free 4.
    var allowsAllHighlightColors: Bool = false
    /// Called when the user taps a color they haven't paid for. The paywall is
    /// presented by ReaderView, outside this hosted view tree.
    var onRequestPremium: () -> Void = {}

    @EnvironmentObject var themeManager: ThemeManager

    /// Animated 0–1 opacity driving the gold flash overlay on the highlighted verses.
    @State private var navFlashOpacity: Double = 0
    /// Verse numbers being flashed — kept set during the fade-out so the overlay
    /// stays on the correct rows while navFlashOpacity animates back to 0.
    @State private var flashVerses: Set<String> = []

    // Non-contiguous selection: each element is a selected verse NUMBER.
    // A Set lets the user pick any combination of verses (e.g. v1 + v5).
    //
    // Keyed by verse number rather than ForEach index because highlights are
    // persisted against verse numbers: indices shift when a translation adds a
    // section heading, which would silently move a saved highlight to the wrong
    // verse. Section headings carry the number "§" and are never selectable —
    // VerseRow gives them no tap gesture at all.
    @State private var selectedVerseNumbers: Set<String> = []

    private var isInSelectionMode: Bool { !selectedVerseNumbers.isEmpty }

    /// The chapter split into verse rows. One parse per render, shared by the
    /// body and the selection helpers below.
    private var verseRows: [(number: String, text: String)] {
        Self.parseVerses(from: content.textContent)
    }

    /// Selected verses in reading order, headings excluded.
    private var orderedSelection: [(number: String, text: String)] {
        verseRows.filter { $0.number != "§" && selectedVerseNumbers.contains($0.number) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Chapter title
            Text(content.reference)
                .font(.title2.bold())
                .foregroundStyle(themeManager.currentTheme.text)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Verse rows — long-press for context menu, tap in selection mode to toggle.
            // Parsed once here and reused; this used to run three times per render.
            let verses = verseRows
            // Build a lookup from verse number → segments for red-letter rendering.
            // uniquingKeysWith: keeps the first occurrence if duplicate verse numbers appear.
            let segsByNumber: [String: [VerseSegment]] = Dictionary(
                content.parsedVerses.map { ($0.number, $0.segments) },
                uniquingKeysWith: { first, _ in first }
            )
            // Topmost selected row, for anchoring the action bubble.
            let firstSelectedIndex = verses.indices.first {
                selectedVerseNumbers.contains(verses[$0].number)
            }
            let chapterHighlights = highlightsVM.colors(forChapter: content.id)
            ForEach(Array(verses.enumerated()), id: \.offset) { index, verse in
                VerseRow(
                    number:            verse.number,
                    text:              verse.text,
                    segments:          segsByNumber[verse.number],
                    showRedLetters:    vm.showRedLetters,
                    font:              bodyFont,
                    spacing:           vm.lineSpacing,
                    alignment:         swiftUIAlignment,
                    theme:             themeManager.currentTheme,
                    navFlashOpacity:   flashVerses.contains(verse.number) ? navFlashOpacity : 0.0,
                    isPlayingVerse:    !playingVerse.isEmpty && verse.number == playingVerse,
                    onBookmarkVerse:   { onLongPressVerse([verse.number], verse.text) },
                    // Section headings (§) are not addressable by the audio player.
                    onTapVerse:        verse.number == "§" ? nil : onTapVerse.map { cb in { cb(verse.number) } },
                    isInSelectionMode: isInSelectionMode,
                    isSelected:        selectedVerseNumbers.contains(verse.number),
                    highlightColorHex: chapterHighlights[verse.number],
                    onToggleSelection: {
                        withAnimation(.spring(duration: 0.25)) {
                            if selectedVerseNumbers.contains(verse.number) {
                                selectedVerseNumbers.remove(verse.number)
                            } else {
                                selectedVerseNumbers.insert(verse.number)
                            }
                        }
                    },
                    isCoachMarkTarget: verse.number == "1"
                )
                // Report this row's bounds if it's the topmost selected verse.
                // overlayPreferenceValue uses this to anchor the bubble popup.
                .anchorPreference(key: FirstSelectedVerseAnchorKey.self, value: .bounds) {
                    firstSelectedIndex == index ? $0 : nil
                }
                // Verse taps/long-presses are off while drawing, but the Prev/Next
                // footer below stays live so it can still be tapped by finger.
                .allowsHitTesting(!isDrawingToolActive)
            }

            Divider()
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // Copyright — required by API.Bible licensing for every translation
            if !content.copyright.isEmpty {
                Text(content.copyright)
                    .font(.caption2)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }

            // Previous / Next chapter navigation
            ChapterNavigationFooter(vm: vm,
                                    isDrawingToolActive: isDrawingToolActive,
                                    metrics: footerMetrics)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    footerMetrics.globalFrame = $0
                }

            // Run-out below the footer so the docked history pills have room to
            // sit underneath "Previous Page" instead of landing on top of it.
            Color.clear.frame(height: 72)
        }
        // Publish the real page height through the shared object. Reported from
        // in here because this view lives inside the scroll view's hosting
        // controller, which preferences cannot escape.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            footerMetrics.pageHeight = $0
        }
        // Float a compact action bubble just below the first selected verse.
        // GeometryReader is always present so the bubble can animate in/out via transition.
        .overlayPreferenceValue(FirstSelectedVerseAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, isInSelectionMode {
                    let rect    = proxy[anchor]
                    // Clamp x so the bubble never clips the horizontal edges.
                    // Half the card's natural width: 8 swatches + the optional
                    // remove button. On a screen too narrow to clamp within,
                    // just centre it rather than pushing it off one side.
                    let halfCard: CGFloat = 160
                    let bubbleX = proxy.size.width <= halfCard * 2
                        ? proxy.size.width / 2
                        : max(halfCard, min(rect.midX, proxy.size.width - halfCard))
                    selectionBubble
                        .fixedSize()
                        .position(x: bubbleX, y: rect.maxY + 28)
                }
            }
        }
        // task(id:) fires on BOTH view appear and value change, unlike onChange which
        // only fires on changes to existing views. This is needed because the parent's
        // .id(content.id) recreates this view tree on every chapter load.
        .task(id: highlightedVerses) {
            if !highlightedVerses.isEmpty {
                flashVerses = highlightedVerses
                withAnimation(.easeInOut(duration: 0.35)) { navFlashOpacity = 1.0 }
            } else {
                withAnimation(.easeOut(duration: 0.8)) { navFlashOpacity = 0.0 }
                // Wait for the fade-out to finish before clearing flashVerses so the
                // overlay stays on the correct rows while it's still fading.
                try? await Task.sleep(for: .seconds(0.9))
                flashVerses = []
            }
        }
        // Zoom is handled at ReaderView level via scaleEffect so that
        // the canvas and notes all scale together with the text.
    }

    // MARK: - Selection Bubble

    /// Compact card that appears below the first selected verse.
    ///
    /// Two rows: the highlight colors on top, then ✕ | label | Bookmark.
    /// Highlighting is the action people reach for most, so it gets the row
    /// that needs no reading.
    private var selectionBubble: some View {
        VStack(spacing: 0) {
            highlightColorRow
            Divider()
            selectionActionRow
        }
        .foregroundStyle(themeManager.currentTheme.primary)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
        .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
    }

    private var highlightColorRow: some View {
        HStack(spacing: 8) {
            ForEach(VerseHighlight.presetColors, id: \.hex) { preset in
                Button {
                    if isColorLocked(preset.hex) {
                        onRequestPremium()
                    } else {
                        applyHighlight(preset.hex)
                    }
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                        )
                        .overlay {
                            if isColorLocked(preset.hex) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isColorLocked(preset.hex)
                                    ? "\(preset.name) highlight, Pro"
                                    : "\(preset.name) highlight")
            }

            // Only offered when it would change something.
            if selectionHasHighlight {
                Divider().frame(height: 22)
                Button {
                    removeHighlight()
                } label: {
                    Image(systemName: "slash.circle")
                        .font(.body.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove highlight")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var selectionActionRow: some View {
        HStack(spacing: 0) {
            // Dismiss / cancel selection
            Button {
                clearSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .accessibilityLabel("Cancel selection")

            Divider().frame(height: 18)

            // How many verses are selected
            Text(selectionLabel)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider().frame(height: 18)

            // Commit bookmark
            Button {
                commitSelection()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bookmark.fill")
                    Text("Bookmark")
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Selection Logic

    private var selectionLabel: String {
        let selection = orderedSelection
        switch selection.count {
        case 0:  return ""
        case 1:  return "Verse \(selection[0].number)"
        default: return "\(selection.count) verses"
        }
    }

    private func clearSelection() {
        withAnimation(.spring(duration: 0.25)) { selectedVerseNumbers = [] }
    }

    private func commitSelection() {
        let selection = orderedSelection
        guard !selection.isEmpty else { clearSelection(); return }
        onLongPressVerse(selection.map(\.number),
                         selection.map(\.text).joined(separator: " "))
        clearSelection()
    }

    // MARK: - Highlighting

    /// True when the user hasn't paid for this color yet.
    /// Mirrors how bookmark colors are already gated, so the same 4 colors are
    /// free in both places and highlights aren't a side door to the other 4.
    private func isColorLocked(_ hex: String) -> Bool {
        !allowsAllHighlightColors && !PremiumLimits.freeBookmarkColors.contains(hex)
    }

    /// True when at least one selected verse already carries a highlight, so the
    /// "remove" button only appears when it would actually do something.
    private var selectionHasHighlight: Bool {
        highlightsVM.hasAnyHighlight(chapterId:    content.id,
                                     verseNumbers: orderedSelection.map(\.number))
    }

    private func applyHighlight(_ hex: String) {
        let numbers = orderedSelection.map(\.number)
        guard !numbers.isEmpty else { clearSelection(); return }
        highlightsVM.setHighlight(chapterId:    content.id,
                                  verseNumbers: numbers,
                                  colorHex:     hex,
                                  userId:       highlightUserId)
        clearSelection()
    }

    private func removeHighlight() {
        let numbers = orderedSelection.map(\.number)
        guard !numbers.isEmpty else { clearSelection(); return }
        highlightsVM.removeHighlight(chapterId:    content.id,
                                     verseNumbers: numbers,
                                     userId:       highlightUserId)
        clearSelection()
    }

    // MARK: - Font

    private var bodyFont: Font {
        let size = vm.fontSize
        switch vm.fontChoice {
        case "Georgia":     return .custom("Georgia",        size: size)
        case "Palatino":    return .custom("Palatino-Roman", size: size)
        case "Baskerville": return .custom("Baskerville",    size: size)
        default:            return .system(size: size)
        }
    }

    private var swiftUIAlignment: TextAlignment {
        switch vm.textAlignment {
        case "center":   return .center
        case "trailing": return .trailing
        default:         return .leading
        }
    }

    // MARK: - Verse Parser
    // Splits the chapter's plain text into individual verse tuples.
    // Detects verse numbers (1–176) appearing as standalone tokens.

    static func parseVerses(from text: String) -> [(number: String, text: String)] {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var verses:      [(String, String)] = []
        var currentNum   = ""
        var currentWords = [String]()

        for word in words {
            // Verse numbers arrive as [N] bracket tokens produced by BibleAPIService.parseHTML.
            // Section headings arrive as [§] tokens.
            if word.hasPrefix("["), word.hasSuffix("]") {
                let stripped = String(word.dropFirst().dropLast())
                if let _ = Int(stripped) {
                    // Normal verse boundary
                    if !currentNum.isEmpty {
                        verses.append((currentNum, currentWords.joined(separator: " ")))
                    }
                    currentNum   = stripped
                    currentWords = []
                    continue
                } else if stripped == "§" {
                    // Section heading boundary
                    if !currentNum.isEmpty {
                        verses.append((currentNum, currentWords.joined(separator: " ")))
                    }
                    currentNum   = "§"
                    currentWords = []
                    continue
                }
            }
            currentWords.append(word)
        }
        if !currentNum.isEmpty {
            verses.append((currentNum, currentWords.joined(separator: " ")))
        }
        return verses.isEmpty ? [("", text)] : verses
    }
}

// MARK: - Single Verse Row

private struct VerseRow: View {

    let number:            String
    let text:              String
    let segments:          [VerseSegment]?   // nil when translation has no markup
    let showRedLetters:    Bool
    let font:              Font
    let spacing:           Double
    let alignment:         TextAlignment
    let theme:             any AppTheme
    /// 0–1 opacity for the gold flash overlay driven by BibleTextView.
    let navFlashOpacity:   Double
    /// True when the audio player is narrating this verse right now.
    let isPlayingVerse:    Bool
    /// Spring-animated scale for the peek effect. Driven by onChange(of: navFlashOpacity).
    @State private var peekScale: CGFloat = 1.0
    let onBookmarkVerse:   () -> Void
    /// When non-nil, tapping this row seeks the audio player to this verse.
    /// Nil when the player is not active — tap does nothing outside selection mode.
    let onTapVerse:        (() -> Void)?
    /// True when any verse is selected (drives dimming of non-selected rows).
    let isInSelectionMode: Bool
    /// True when this row is currently in the selection set.
    let isSelected:        Bool
    /// The user's highlight color for this verse, or nil when not highlighted.
    let highlightColorHex: String?
    /// Toggles this verse in/out of the selection. Called on tap (in selection mode) or
    /// when the user picks "Select Verse" from the context menu (to start a selection).
    let onToggleSelection: () -> Void
    var isCoachMarkTarget: Bool = false

    var body: some View {
        if number == "§" {
            // Section heading — larger, bold title like YouVersion, with breathing room
            Text(text)
                .font(.title3.weight(.heavy))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 12)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Small superscript-style verse number
                if !number.isEmpty {
                    Text(number)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.primary.opacity(0.7))
                        .frame(minWidth: 22, alignment: .trailing)
                        .padding(.top, 3)
                }
                // Verse text — use AttributedString for red letters when available
                verseContent
            }
            .coachMark("reader-verse-row", active: isCoachMarkTarget)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, isSelected ? 28 : 20)
            .padding(.trailing, 20)
            .padding(.vertical, 4)
            .fontWeight(isSelected ? .semibold : .regular)
            // Audio-playing verse: left accent bar marks current verse
            .overlay(alignment: .leading) {
                if isPlayingVerse {
                    Rectangle()
                        .fill(theme.primary)
                        .frame(width: 3)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isPlayingVerse)
            // Dim non-selected verses; lift selected ones with scale + shadow.
            .opacity(isInSelectionMode && !isSelected ? 0.35 : 1.0)
            .scaleEffect(isSelected ? 1.02 : 1.0, anchor: .leading)
            // Spring peek: verse pops out when flash fires then settles back smoothly.
            .scaleEffect(peekScale, anchor: .leading)
            .shadow(color: isSelected ? .black.opacity(0.10) : .clear, radius: 6, y: 3)
            .zIndex(isSelected ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isInSelectionMode)
            .animation(.spring(duration: 0.3, bounce: 0.2), value: isSelected)
            .onChange(of: navFlashOpacity) { _, newVal in
                if newVal > 0 {
                    // Flash started — pop out with a bouncy spring, hold 2 s, then settle.
                    // The color flash clears 1 s after the pop returns, so the gold lingers
                    // as a quieter glow after the verse has already settled back.
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.38)) { peekScale = 1.09 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { peekScale = 1.0 }
                    }
                } else {
                    // Safety net: if flash is cancelled early, snap peek back too.
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { peekScale = 1.0 }
                }
            }
            .contentShape(Rectangle())
            // Tap: in selection mode → toggle; player active → seek to verse; else → no-op.
            .onTapGesture {
                if isInSelectionMode {
                    onToggleSelection()
                } else if let onTapVerse {
                    onTapVerse()
                }
            }
            // Context menu coordinates natively with UIScrollView — iOS yields to
            // scrolling if the user pans before the menu fires, so there is no gesture conflict.
            // Suppressed in selection mode so taps freely toggle verses.
            .contextMenu {
                if !isInSelectionMode {
                    Button { onBookmarkVerse() } label: {
                        Label("Bookmark Verse", systemImage: "bookmark")
                    }
                    Button { onToggleSelection() } label: {
                        Label("Select Verse", systemImage: "checkmark.circle")
                    }
                    if let onTapVerse {
                        Divider()
                        Button { onTapVerse() } label: {
                            Label("Play from here", systemImage: "play.circle")
                        }
                    }
                }
            }
        }
    }

    private var verseContent: some View {
        // Both the red-letter and plain cases go through one AttributedString so
        // the highlight is applied in exactly one place.
        Text(attributedVerse)
            .font(font)
            .lineSpacing(spacing)
            .multilineTextAlignment(alignment)
            .overlay(
                // AttributedString colors override foregroundStyle, so the flash
                // is a separate plain Text on top — solid gold regardless of red
                // letters or highlighting underneath.
                Text(text)
                    .font(font)
                    .foregroundStyle(navHighlightColor)
                    .lineSpacing(spacing)
                    .multilineTextAlignment(alignment)
                    .opacity(navFlashOpacity)
            )
    }

    /// Warm gold color used for the brief text-color flash when navigating from Community.
    private var navHighlightColor: Color { Color(red: 0.85, green: 0.60, blue: 0.10) }

    /// The verse with Jesus' words in red where the translation marks them, and
    /// the user's highlight painted behind the words when there is one.
    ///
    /// The highlight is a per-run `backgroundColor` rather than a band behind the
    /// whole row, so it hugs the text and re-wraps with it — the way a highlighter
    /// behaves on paper, and what the Bible app does. It also avoids measuring
    /// text geometry, which cannot escape the Reader's hosting controller anyway.
    private var attributedVerse: AttributedString {
        let runs: [VerseSegment]
        if showRedLetters, let segs = segments, segs.contains(where: { $0.isRedLetter }) {
            runs = segs
        } else {
            runs = [VerseSegment(text: text, isRedLetter: false)]
        }

        // Painted at partial strength: four of the eight themes are dark, and a
        // solid pale fill behind light text is unreadable.
        let fill = highlightColorHex.map {
            Color(hex: $0).opacity(VerseHighlight.fillOpacity(onDarkTheme: theme.isDarkSurface))
        }

        var result = AttributedString()
        for seg in runs {
            var part = AttributedString(seg.text)
            part.swiftUI.foregroundColor = seg.isRedLetter ? theme.redLetter : theme.text
            if let fill { part.swiftUI.backgroundColor = fill }
            result += part
        }
        return result
    }

    private func frameAlignment(for ta: TextAlignment) -> Alignment {
        switch ta {
        case .center:   return .center
        case .trailing: return .trailing
        default:        return .leading
        }
    }
}

// MARK: - Footer Geometry

/// Where the Prev/Next footer and its two buttons are on screen.
///
/// This is a reference type on purpose. The page content is hosted inside
/// ZoomScrollView's UIHostingController, and SwiftUI **preferences do not cross a
/// UIHostingController boundary** — anything reported with `.preference` from in
/// here is discarded before ReaderView can read it. A shared object does cross,
/// because both sides hold the same instance.
///
/// ReaderView uses these to put tap targets over the buttons (so a finger can
/// reach them while the drawing canvas is on top) and to tuck the history pills
/// in underneath the footer.
final class ReaderFooterMetrics: ObservableObject {
    /// The whole footer strip in screen coordinates. This single measurement is
    /// enough: the strip's own padding fixes where Previous and Next sit inside
    /// it, so ReaderView can place tap targets without measuring each button.
    @Published var globalFrame: CGRect = .zero

    /// Horizontal inset of the buttons inside the strip — must match the
    /// `.padding(.horizontal, …)` on ChapterNavigationFooter below.
    static let horizontalInset: CGFloat = 24

    /// Full height of the laid-out page, measured from inside the scroll view.
    ///
    /// ReaderView's own `contentHeight` cannot be used for this: it is fed by
    /// `ContentHeightKey`, a PreferenceKey read from OUTSIDE the hosting
    /// controller, so the value never arrives and the state stays at the 100pt
    /// placeholder set on every chapter change. Anything that needs a real page
    /// height should read this instead.
    @Published var pageHeight: CGFloat = 0

    var height:     CGFloat { globalFrame.height }
    var globalMaxY: CGFloat { globalFrame == .zero ? .greatestFiniteMagnitude : globalFrame.maxY }
}

// MARK: - Prev / Next Footer

private struct ChapterNavigationFooter: View {

    @ObservedObject var vm: ReaderViewModel
    @EnvironmentObject var themeManager: ThemeManager

    /// True while a drawing tool is selected. Pencil touches then fall through to
    /// the canvas above these buttons so drawing across them still draws, while a
    /// finger can still tap them.
    var isDrawingToolActive: Bool = false
    @ObservedObject var metrics: ReaderFooterMetrics

    var body: some View {
        HStack {
            Label("Previous Page", systemImage: "chevron.left")
                .font(.subheadline.weight(.medium))
                .opacity(isFirstChapter ? 0.35 : 1)
                .fingerTappable(passPencilThrough: isDrawingToolActive,
                                label: "Previous Page") {
                    guard !isFirstChapter else { return }
                    Task { await vm.goToPreviousChapter() }
                }

            Spacer()

            if let chapter = vm.selectedChapter {
                Text(chapter.reference)
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
            }

            Spacer()

            Label("Next Page", systemImage: "chevron.right")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .opacity(isLastChapter ? 0.35 : 1)
                .fingerTappable(passPencilThrough: isDrawingToolActive,
                                label: "Next Page") {
                    guard !isLastChapter else { return }
                    Task { await vm.goToNextChapter() }
                }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .foregroundStyle(themeManager.currentTheme.primary)
    }

    private var isFirstChapter: Bool {
        guard let c = vm.selectedChapter else { return true }
        return vm.chapters.first?.id == c.id
    }
    private var isLastChapter: Bool {
        guard let c = vm.selectedChapter else { return true }
        return vm.chapters.last?.id == c.id
    }
}
