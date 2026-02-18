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
    let onLongPressVerse:   (String, String) -> Void  // (verseNumber, verseText)

    @EnvironmentObject var themeManager: ThemeManager
    @GestureState private var zoomDelta: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Chapter title
            Text(content.reference)
                .font(.title2.bold())
                .foregroundStyle(themeManager.currentTheme.text)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Verse rows — each one can be long-pressed to bookmark
            let verses = Self.parseVerses(from: content.textContent)
            ForEach(Array(verses.enumerated()), id: \.offset) { _, verse in
                VerseRow(
                    number:      verse.number,
                    text:        verse.text,
                    font:        bodyFont,
                    spacing:     vm.lineSpacing,
                    alignment:   swiftUIAlignment,
                    theme:       themeManager.currentTheme,
                    onLongPress: { onLongPressVerse(verse.number, verse.text) }
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
        // Pinch-to-zoom: two-finger spread/pinch adjusts font size
        .gesture(
            MagnificationGesture()
                .updating($zoomDelta) { value, state, _ in state = value }
                .onEnded { value in
                    vm.fontSize = min(36, max(12, vm.fontSize * value))
                }
        )
        .scaleEffect(zoomDelta, anchor: .topLeading)
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

    let number:      String
    let text:        String
    let font:        Font
    let spacing:     Double
    let alignment:   TextAlignment
    let theme:       any AppTheme
    let onLongPress: () -> Void

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
        .background(isHighlighted ? theme.primary.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) {
            isHighlighted = false
            onLongPress()
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) { isHighlighted = pressing }
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
