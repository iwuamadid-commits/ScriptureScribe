//
//  ChapterSelectorRow.swift
//  ScriptureScribe
//
//  A horizontal scrollable row of chapter numbers directly below the book row.
//  Tapping a number jumps to that chapter. The current chapter is highlighted.
//

import SwiftUI

struct ChapterSelectorRow: View {

    @ObservedObject var vm: ReaderViewModel
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(vm.chapters) { chapter in
                        ChapterChip(
                            chapter:    chapter,
                            isSelected: vm.selectedChapter?.id == chapter.id,
                            theme:      themeManager.currentTheme
                        )
                        .id(chapter.id)
                        .onTapGesture {
                            Task { await vm.selectChapter(chapter) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(themeManager.currentTheme.surface)
            // Scroll the selected chapter into view automatically
            .onChange(of: vm.selectedChapter?.id) { _, newID in
                if let id = newID {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }
}

// MARK: - Single Chapter Number Chip

private struct ChapterChip: View {

    let chapter:    BibleChapter
    let isSelected: Bool
    let theme:      any AppTheme

    var body: some View {
        Text(chapter.number)
            .font(.footnote.weight(isSelected ? .bold : .regular))
            .frame(minWidth: 32)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(isSelected ? theme.primary : Color.clear)
            .foregroundStyle(isSelected ? Color.white : theme.text)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : theme.border, lineWidth: 1)
            )
    }
}
