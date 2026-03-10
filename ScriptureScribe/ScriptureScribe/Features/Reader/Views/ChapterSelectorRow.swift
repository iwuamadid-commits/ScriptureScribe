//
//  ChapterSelectorRow.swift
//  ScriptureScribe
//
//  Horizontal row of chapter number chips. Chapters that have saved annotations
//  show a small colored dot indicator below the number.
//  The selected chapter pill slides smoothly to the new selection.
//

import SwiftUI

struct ChapterSelectorRow: View {

    // Passed-in plain values only — no @ObservedObject so that unrelated
    // state changes (isLoadingContent, annotations loading, etc.) never
    // interrupt the selection highlight or reset the scroll position.
    let chapters:             [BibleChapter]
    let selectedChapterId:    String?
    let annotatedChapterIds:  Set<String>   // chapters that have a dot indicator
    let vm:                   ReaderViewModel   // plain ref for tap callbacks
    var onOpenBrowser: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(chapters) { chapter in
                        let isSelected = selectedChapterId == chapter.id
                        ChapterChip(
                            chapter:       chapter,
                            isSelected:    isSelected,
                            hasAnnotation: annotatedChapterIds.contains(chapter.id),
                            theme:         themeManager.currentTheme,
                            isCompact:     isCompact
                        )
                        // Extra horizontal layout space lets the scaled chip expand
                        // without bleeding into its neighbors.
                        .padding(.horizontal, isSelected ? 3 : 0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.85), value: isSelected)
                        .id(chapter.id)
                        .onTapGesture {
                            if isSelected {
                                onOpenBrowser()
                            } else {
                                Task {
                                    await vm.loadInitialData()
                                    await vm.selectChapter(chapter)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, isCompact ? 3 : 6)
            }
            .background(themeManager.currentTheme.surface)
            // Scroll the selected chapter into view — on first appearance and on change
            .onAppear {
                if let id = selectedChapterId {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: selectedChapterId) { _, newID in
                guard let id = newID else { return }
                withAnimation(.spring(response: 1.0, dampingFraction: 0.85)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Chapter Chip

private struct ChapterChip: View {

    let chapter:       BibleChapter
    let isSelected:    Bool
    let hasAnnotation: Bool
    let theme:         any AppTheme
    var isCompact:     Bool = false

    var body: some View {
        VStack(spacing: isCompact ? 1 : 2) {
            Text(chapter.number)
                .font(isCompact
                      ? .caption2.weight(isSelected ? .bold : .regular)
                      : .footnote.weight(isSelected ? .bold : .regular))
                .frame(minWidth: isCompact ? 26 : 32)
                .padding(.horizontal, isCompact ? 4 : 6)
                .padding(.vertical, isCompact ? 4 : 6)
                .foregroundStyle(isSelected ? Color.white : theme.text)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.border, lineWidth: 1)
                            .opacity(isSelected ? 0 : 1)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.primary)
                            .opacity(isSelected ? 1 : 0)
                    }
                }

            // Annotation dot indicator
            Circle()
                .fill(theme.primary)
                .frame(width: isCompact ? 4 : 5, height: isCompact ? 4 : 5)
                .opacity(hasAnnotation ? 1 : 0)
        }
        .scaleEffect(isSelected ? 1.12 : 1.0)
        .animation(.spring(response: 0.8, dampingFraction: 0.85), value: isSelected)
    }
}
