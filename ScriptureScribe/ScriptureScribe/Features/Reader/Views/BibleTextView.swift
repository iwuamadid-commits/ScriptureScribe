//
//  BibleTextView.swift
//  ScriptureScribe
//
//  Displays Bible text verse-by-verse so each verse can be long-pressed to bookmark.
//  This view has NO internal ScrollView — the parent ReaderView owns the scroll,
//  which allows the annotation canvas to scroll with the text.
//

import SwiftUI

struct BibleTextView: View {

    let content:            BibleChapterContent
    @ObservedObject var vm: ReaderViewModel
    let onLongPressVerse:   (String, String?, String) -> Void  // (startVerse, endVerse?, text)

    @EnvironmentObject var themeManager: ThemeManager

    @State private var selectedRangeStart: Int?
    @State private var selectedRangeEnd:   Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Chapter title
            Text(content.reference)
                .font(.title2.bold())
                .foregroundStyle(themeManager.currentTheme.text)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Verse rows — long-press and drag to select a range
            let verses = Self.parseVerses(from: content.textContent)
            ForEach(Array(verses.enumerated()), id: \.offset) { index, verse in
                VerseRow(
                    number:                     verse.number,
                    text:                       verse.text,
                    font:                       bodyFont,
                    spacing:                    vm.lineSpacing,
                    alignment:                  swiftUIAlignment,
                    theme:                      themeManager.currentTheme,
                    isInSelectedRange:          isVerseInRange(index),
                    onStartRangeSelection:      { startRangeSelection(at: index) },
                    onUpdateRangeSelection:     { dragHeight in updateRangeSelection(from: index, dragHeight: dragHeight, totalVerses: verses.count) },
                    onCompleteRangeSelection:   { completeRangeSelection(verses: verses) }
                )
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
                .padding(.bottom, 40)
        }
        // Zoom is handled at ReaderView level via scaleEffect so that
        // the canvas and notes all scale together with the text.
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

    // MARK: - Range Selection

    private func isVerseInRange(_ index: Int) -> Bool {
        guard let start = selectedRangeStart, let end = selectedRangeEnd else {
            return false
        }
        let minIndex = min(start, end)
        let maxIndex = max(start, end)
        return index >= minIndex && index <= maxIndex
    }

    private func startRangeSelection(at index: Int) {
        selectedRangeStart = index
        selectedRangeEnd   = index
    }

    private func updateRangeSelection(from startIndex: Int, dragHeight: CGFloat, totalVerses: Int) {
        // Estimate verse height (roughly 40-50pt depending on font size and line spacing)
        let estimatedVerseHeight: CGFloat = 45
        let draggedVerses = Int(round(dragHeight / estimatedVerseHeight))

        let endIndex = startIndex + draggedVerses
        selectedRangeEnd = max(0, min(totalVerses - 1, endIndex))
    }

    private func completeRangeSelection(verses: [(number: String, text: String)]) {
        guard let start = selectedRangeStart, let end = selectedRangeEnd else {
            return
        }

        let minIndex = min(start, end)
        let maxIndex = max(start, end)

        let startVerse = verses[minIndex].number
        let endVerse   = verses[maxIndex].number

        // Combine text from all verses in range
        let combinedText = verses[minIndex...maxIndex]
            .map { $0.text }
            .joined(separator: " ")

        // If it's a single verse, pass nil for endVerse
        let endVerseOrNil = (startVerse == endVerse) ? nil : endVerse

        onLongPressVerse(startVerse, endVerseOrNil, combinedText)

        // Clear selection
        selectedRangeStart = nil
        selectedRangeEnd   = nil
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
            // Try to match verse numbers in square brackets: [1], [2], etc.
            if word.hasPrefix("["), word.hasSuffix("]") {
                let stripped = String(word.dropFirst().dropLast())
                if let num = Int(stripped), num >= 1, num <= 176 {
                    if !currentNum.isEmpty {
                        verses.append((currentNum, currentWords.joined(separator: " ")))
                    }
                    currentNum   = stripped
                    currentWords = []
                    continue
                }
            }
            // Also try plain numbers (for translations that don't use brackets)
            if let num = Int(word), num >= 1, num <= 176 {
                if !currentNum.isEmpty {
                    verses.append((currentNum, currentWords.joined(separator: " ")))
                }
                currentNum   = word
                currentWords = []
            } else {
                currentWords.append(word)
            }
        }
        if !currentNum.isEmpty {
            verses.append((currentNum, currentWords.joined(separator: " ")))
        }
        return verses.isEmpty ? [("", text)] : verses
    }
}

// MARK: - Single Verse Row

private struct VerseRow: View {

    let number:                    String
    let text:                      String
    let font:                      Font
    let spacing:                   Double
    let alignment:                 TextAlignment
    let theme:                     any AppTheme
    let isInSelectedRange:         Bool
    let onStartRangeSelection:     () -> Void
    let onUpdateRangeSelection:    (CGFloat) -> Void
    let onCompleteRangeSelection:  () -> Void

    @State private var isHighlighted = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Small superscript-style verse number
            if !number.isEmpty {
                Text(number)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.primary.opacity(0.7))
                    .frame(minWidth: 22, alignment: .trailing)
                    .padding(.top, 3)
            }
            // Verse text
            Text(text)
                .font(font)
                .foregroundStyle(theme.text)
                .lineSpacing(spacing)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity, alignment: frameAlignment(for: alignment))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(backgroundHighlight)
        .contentShape(Rectangle())
        .gesture(rangeSelectionGesture)
    }

    private var backgroundHighlight: some View {
        Group {
            if isInSelectedRange {
                theme.primary.opacity(0.20)
            } else if isHighlighted {
                theme.primary.opacity(0.10)
            } else {
                Color.clear
            }
        }
    }

    private var rangeSelectionGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onChanged { _ in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHighlighted = true
                }
            }
            .onEnded { _ in
                isHighlighted = false
                onStartRangeSelection()
            }
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if let dragValue = drag {
                        onUpdateRangeSelection(dragValue.translation.height)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                isHighlighted = false
                onCompleteRangeSelection()
            }
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
