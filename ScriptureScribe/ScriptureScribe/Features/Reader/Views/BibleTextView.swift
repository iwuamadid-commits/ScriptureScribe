//
//  BibleTextView.swift
//  ScriptureScribe
//
//  Displays Bible text verse-by-verse so each verse can be long-pressed to bookmark.
//  This view has NO internal ScrollView — the parent ReaderView owns the scroll,
//  which allows the annotation canvas to scroll with the text.
//

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

    @EnvironmentObject var themeManager: ThemeManager

    /// Animated 0–1 opacity driving the gold flash overlay on the highlighted verses.
    @State private var navFlashOpacity: Double = 0
    /// Verse numbers being flashed — kept set during the fade-out so the overlay
    /// stays on the correct rows while navFlashOpacity animates back to 0.
    @State private var flashVerses: Set<String> = []

    // Non-contiguous selection: each element is the ForEach index of a selected verse.
    // Using a Set<Int> lets the user pick any combination of verses (e.g. v1 + v5).
    @State private var selectedIndices: Set<Int> = []

    private var isInSelectionMode: Bool { !selectedIndices.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Chapter title
            Text(content.reference)
                .font(.title2.bold())
                .foregroundStyle(themeManager.currentTheme.text)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Verse rows — long-press for context menu, tap in selection mode to toggle
            let verses = Self.parseVerses(from: content.textContent)
            // Build a lookup from verse number → segments for red-letter rendering.
            // uniquingKeysWith: keeps the first occurrence if duplicate verse numbers appear.
            let segsByNumber: [String: [VerseSegment]] = Dictionary(
                content.parsedVerses.map { ($0.number, $0.segments) },
                uniquingKeysWith: { first, _ in first }
            )
            let firstSelectedIndex = selectedIndices.min()
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
                    isSelected:        selectedIndices.contains(index),
                    onToggleSelection: {
                        withAnimation(.spring(duration: 0.25)) {
                            if selectedIndices.contains(index) {
                                selectedIndices.remove(index)
                            } else {
                                selectedIndices.insert(index)
                            }
                        }
                    }
                )
                // Report this row's bounds if it's the topmost selected verse.
                // overlayPreferenceValue uses this to anchor the bubble popup.
                .anchorPreference(key: FirstSelectedVerseAnchorKey.self, value: .bounds) {
                    firstSelectedIndex == index ? $0 : nil
                }
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
            ChapterNavigationFooter(vm: vm)
        }
        // Float a compact action bubble just below the first selected verse.
        // GeometryReader is always present so the bubble can animate in/out via transition.
        .overlayPreferenceValue(FirstSelectedVerseAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, isInSelectionMode {
                    let rect    = proxy[anchor]
                    // Clamp x so the bubble never clips the horizontal edges.
                    let bubbleX = max(110, min(rect.midX, proxy.size.width - 110))
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

    /// Compact pill that appears below the first selected verse.
    /// Contains: ✕ dismiss  |  label  |  Bookmark action
    private var selectionBubble: some View {
        HStack(spacing: 0) {
            // Dismiss / cancel selection
            Button {
                withAnimation(.spring(duration: 0.25)) { selectedIndices = [] }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

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
        .foregroundStyle(themeManager.currentTheme.primary)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
        .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
    }

    // MARK: - Selection Logic

    private var selectionLabel: String {
        let verses = Self.parseVerses(from: content.textContent)
        let validCount = selectedIndices.filter { $0 < verses.count && verses[$0].number != "§" }.count
        if validCount == 0 { return "" }
        if validCount == 1,
           let idx = selectedIndices.first(where: { $0 < verses.count && verses[$0].number != "§" }) {
            return "Verse \(verses[idx].number)"
        }
        return "\(validCount) verses"
    }

    private func commitSelection() {
        guard !selectedIndices.isEmpty else { return }
        let verses  = Self.parseVerses(from: content.textContent)
        let sorted  = selectedIndices.sorted()
        let validIndices = sorted.filter { $0 < verses.count && verses[$0].number != "§" }
        guard !validIndices.isEmpty else {
            withAnimation(.spring(duration: 0.25)) { selectedIndices = [] }
            return
        }
        let verseNumbers = validIndices.map { verses[$0].number }
        let combinedText = validIndices
            .map    { verses[$0].text }
            .joined(separator: " ")
        onLongPressVerse(verseNumbers, combinedText)
        withAnimation(.spring(duration: 0.25)) { selectedIndices = [] }
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
    /// Toggles this verse in/out of the selection. Called on tap (in selection mode) or
    /// when the user picks "Select Verse" from the context menu (to start a selection).
    let onToggleSelection: () -> Void

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

    @ViewBuilder
    private var verseContent: some View {
        if showRedLetters, let segs = segments, segs.contains(where: { $0.isRedLetter }) {
            // Show the red-letter text underneath; overlay a solid-gold version whose
            // opacity is animated in/out by navFlashOpacity.
            Text(attributedString(from: segs))
                .font(font)
                .lineSpacing(spacing)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity, alignment: frameAlignment(for: alignment))
                .overlay(
                    // AttributedString colors override foregroundStyle, so use plain
                    // Text(text) here — the flash is solid gold regardless of red letters.
                    Text(text)
                        .font(font)
                        .foregroundStyle(navHighlightColor)
                        .lineSpacing(spacing)
                        .multilineTextAlignment(alignment)
                        .frame(maxWidth: .infinity, alignment: frameAlignment(for: alignment))
                        .opacity(navFlashOpacity)
                )
        } else {
            // Plain text: overlay a gold copy whose opacity fades in then out.
            Text(text)
                .font(font)
                .foregroundStyle(theme.text)
                .lineSpacing(spacing)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity, alignment: frameAlignment(for: alignment))
                .overlay(
                    Text(text)
                        .font(font)
                        .foregroundStyle(navHighlightColor)
                        .lineSpacing(spacing)
                        .multilineTextAlignment(alignment)
                        .frame(maxWidth: .infinity, alignment: frameAlignment(for: alignment))
                        .opacity(navFlashOpacity)
                )
        }
    }

    /// Warm gold color used for the brief text-color flash when navigating from Community.
    private var navHighlightColor: Color { Color(red: 0.85, green: 0.60, blue: 0.10) }

    /// Builds an AttributedString that colors Jesus' words in redLetter and all other text normally.
    private func attributedString(from segs: [VerseSegment]) -> AttributedString {
        var result = AttributedString()
        for seg in segs {
            var part = AttributedString(seg.text)
            part.swiftUI.foregroundColor = seg.isRedLetter ? theme.redLetter : theme.text
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

// MARK: - Prev / Next Footer

private struct ChapterNavigationFooter: View {

    @ObservedObject var vm: ReaderViewModel
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack {
            Button { Task { await vm.goToPreviousChapter() } } label: {
                Label("Previous", systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(isFirstChapter)

            Spacer()

            if let chapter = vm.selectedChapter {
                Text(chapter.reference)
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
            }

            Spacer()

            Button { Task { await vm.goToNextChapter() } } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
            }
            .disabled(isLastChapter)
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
