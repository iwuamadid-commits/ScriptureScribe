//
//  BibleTextView.swift
//  ScriptureScribe
//
//  Displays the actual Bible text for the current chapter.
//  Supports custom fonts, font size, line spacing, and pinch-to-zoom.
//  Shows a required copyright footer at the bottom of every chapter.
//

import SwiftUI

struct BibleTextView: View {

    let content: BibleChapterContent

    @ObservedObject var vm: ReaderViewModel
    @EnvironmentObject var themeManager: ThemeManager

    // Pinch-to-zoom state
    @GestureState private var zoomDelta: CGFloat = 1.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Chapter reference title (e.g. "Genesis 1")
                Text(content.reference)
                    .font(.title2.bold())
                    .foregroundStyle(themeManager.currentTheme.text)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // Bible text
                Text(content.textContent)
                    .font(bodyFont)
                    .foregroundStyle(themeManager.currentTheme.text)
                    .lineSpacing(vm.lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .scaleEffect(zoomDelta, anchor: .topLeading)

                Divider()
                    .padding(.horizontal, 20)

                // Copyright statement — required by API.Bible licensing for every translation
                if !content.copyright.isEmpty {
                    Text(content.copyright)
                        .font(.caption2)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }

                // Previous / Next chapter navigation at bottom of page
                ChapterNavigationFooter(vm: vm)
                    .padding(.bottom, 32)
            }
        }
        .background(themeManager.currentTheme.background)
        // Pinch-to-zoom: adjusts font size up or down
        .gesture(
            MagnificationGesture()
                .updating($zoomDelta) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    // Clamp font size between 12 and 36
                    vm.fontSize = min(36, max(12, vm.fontSize * value))
                }
        )
    }

    // MARK: - Font

    private var bodyFont: Font {
        let size = vm.fontSize
        switch vm.fontChoice {
        case "Georgia":  return .custom("Georgia",       size: size)
        case "Palatino": return .custom("Palatino-Roman", size: size)
        case "Baskerville": return .custom("Baskerville", size: size)
        default:         return .system(size: size)
        }
    }
}

// MARK: - Previous / Next Footer

private struct ChapterNavigationFooter: View {

    @ObservedObject var vm: ReaderViewModel
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack {
            // Previous chapter
            Button {
                Task { await vm.goToPreviousChapter() }
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(isFirstChapter)

            Spacer()

            // Current position label
            if let chapter = vm.selectedChapter {
                Text(chapter.reference)
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
            }

            Spacer()

            // Next chapter
            Button {
                Task { await vm.goToNextChapter() }
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon) // icon on right
                    .font(.subheadline.weight(.medium))
            }
            .disabled(isLastChapter)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .foregroundStyle(themeManager.currentTheme.primary)
    }

    private var isFirstChapter: Bool {
        guard let current = vm.selectedChapter else { return true }
        return vm.chapters.first?.id == current.id
    }

    private var isLastChapter: Bool {
        guard let current = vm.selectedChapter else { return true }
        return vm.chapters.last?.id == current.id
    }
}
