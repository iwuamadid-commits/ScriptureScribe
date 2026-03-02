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
    @EnvironmentObject var themeManager: ThemeManager

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
                            theme:         themeManager.currentTheme
                        )
                        // Extra horizontal layout space lets the scaled chip expand
                        // without bleeding into its neighbors.
                        .padding(.horizontal, isSelected ? 3 : 0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
                        .id(chapter.id)
                        .onTapGesture {
                            Task {
                                await vm.loadInitialData()
                                await vm.selectChapter(chapter)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(themeManager.currentTheme.surface)
            // Scroll the selected chapter into view — on first appearance and on change
            .onAppear {
                if let id = selectedChapterId {
                    DispatchQueue.main.async {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onChange(of: selectedChapterId) { _, newID in
                guard let id = newID else { return }
                DispatchQueue.main.async {
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

    var body: some View {
        VStack(spacing: 2) {
            Text(chapter.number)
                .font(.footnote.weight(isSelected ? .bold : .regular))
                .frame(minWidth: 32)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
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
                .frame(width: 5, height: 5)
                .opacity(hasAnnotation ? 1 : 0)
        }
        .scaleEffect(isSelected ? 1.12 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}
