//
//  ChapterSelectorRow.swift
//  ScriptureScribe
//
//  Horizontal row of chapter number chips. Chapters that have saved annotations
//  show a small colored dot indicator below the number.
//

import SwiftUI

struct ChapterSelectorRow: View {

    @ObservedObject var vm:           ReaderViewModel
    @ObservedObject var annotationVM: AnnotationViewModel
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(vm.chapters) { chapter in
                        ChapterChip(
                            chapter:       chapter,
                            isSelected:    vm.selectedChapter?.id == chapter.id,
                            hasAnnotation: annotationVM.hasAnnotation(for: chapter.id),
                            theme:         themeManager.currentTheme
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
            .onChange(of: vm.selectedChapter?.id) { _, newID in
                if let id = newID {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
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
                .background(isSelected ? theme.primary : Color.clear)
                .foregroundStyle(isSelected ? Color.white : theme.text)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.clear : theme.border, lineWidth: 1)
                )

            // Annotation dot indicator
            Circle()
                .fill(theme.primary)
                .frame(width: 5, height: 5)
                .opacity(hasAnnotation ? 1 : 0)
        }
    }
}
