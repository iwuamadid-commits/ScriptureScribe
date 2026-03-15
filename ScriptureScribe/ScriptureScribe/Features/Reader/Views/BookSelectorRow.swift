//
//  BookSelectorRow.swift
//  ScriptureScribe
//
//  A horizontal scrollable row of Bible book names at the top of the reader.
//  The selected book is highlighted with a pill that slides to the new selection.
//  A sort button lets the user switch between canonical order (Genesis → Revelation)
//  and A–Z order. Tapping the already-selected book opens the full-screen book browser.
//

import SwiftUI

struct BookSelectorRow: View {

    // Passed-in values only — no @ObservedObject on vm so that changes to
    // isLoadingContent / chapterContent / chapters don't interrupt the pill animation.
    let sortedBooks:    [BibleBook]
    let selectedBookId: String?
    let bookSortOrder:  ReaderViewModel.SortOrder
    let isLoadingBooks: Bool
    let vm:             ReaderViewModel             // plain ref for actions
    var onOpenBrowser: () -> Void
    var showCoachMarks: Bool = true
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                // Sort toggle button (canonical ↔ alphabetical)
                Button {
                    withAnimation {
                        vm.bookSortOrder = bookSortOrder == .canonical ? .alphabetical : .canonical
                    }
                } label: {
                    Image(systemName: bookSortOrder == .canonical ? "list.number" : "textformat.abc")
                        .font(isCompact ? .caption : .footnote)
                        .foregroundStyle(themeManager.currentTheme.primary)
                        .frame(width: isCompact ? 28 : 36, height: isCompact ? 28 : 36)
                        .coachMark("reader-sort-button", active: showCoachMarks)
                }
                .padding(.leading, 8)
                .help(bookSortOrder == .canonical ? "Switch to A–Z order" : "Switch to Bible order")

                // Scrollable list of book names
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(sortedBooks) { book in
                            // Show testament divider before the first NT book (canonical order only)
                            if bookSortOrder == .canonical && book.id == Self.firstNTBookId(in: sortedBooks) {
                                TestamentDivider(label: "NT", theme: themeManager.currentTheme, isCompact: isCompact)
                            }

                            let isSelected = selectedBookId == book.id
                            BookChip(
                                book:       book,
                                isSelected: isSelected,
                                theme:      themeManager.currentTheme,
                                isCompact:  isCompact
                            )
                            // Extra horizontal layout space lets the scaled chip expand
                            // without bleeding into its neighbors.
                            .padding(.horizontal, isSelected ? 4 : 0)
                            .animation(.spring(response: 0.8, dampingFraction: 0.85), value: isSelected)
                            .coachMark("reader-selected-book", active: isSelected && showCoachMarks)
                            .id(book.id)
                            .onTapGesture {
                                if isSelected {
                                    onOpenBrowser()
                                } else {
                                    Task {
                                        await vm.loadInitialData()
                                        await vm.selectBook(book)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, isCompact ? 3 : 6)
                }

                // Loading spinner while books are being fetched
                if isLoadingBooks {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 8)
                }
            }
            .background(themeManager.currentTheme.surface)
            // Scroll the selected book into view — on first appearance and on change
            .onAppear {
                if let id = selectedBookId {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: selectedBookId) { _, newID in
                if let id = newID {
                    withAnimation(.spring(response: 1.0, dampingFraction: 0.85)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Returns the ID of the first New Testament book in the given list, or nil.
    static func firstNTBookId(in books: [BibleBook]) -> String? {
        books.first(where: { BibleBook.ntBookIds.contains($0.id) })?.id
    }
}

// MARK: - Testament Divider

private struct TestamentDivider: View {
    let label:     String
    let theme:     any AppTheme
    var isCompact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            // Thin vertical line
            RoundedRectangle(cornerRadius: 1)
                .fill(theme.primary.opacity(0.5))
                .frame(width: 1.5, height: isCompact ? 18 : 22)

            // Label in primary/indicator color
            Text(label)
                .font(.system(size: isCompact ? 9 : 10, weight: .bold))
                .foregroundStyle(theme.primary)

            // Thin vertical line
            RoundedRectangle(cornerRadius: 1)
                .fill(theme.primary.opacity(0.5))
                .frame(width: 1.5, height: isCompact ? 18 : 22)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Single Book Chip

private struct BookChip: View {

    let book:       BibleBook
    let isSelected: Bool
    let theme:      any AppTheme
    var isCompact:  Bool = false

    var body: some View {
        Text(book.name)
            .font(isCompact
                  ? .caption2.weight(isSelected ? .bold : .regular)
                  : .footnote.weight(isSelected ? .bold : .regular))
            .lineLimit(1)
            .padding(.horizontal, isCompact ? 7 : 10)
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
            .scaleEffect(isSelected ? 1.12 : 1.0)
            .animation(.spring(response: 0.8, dampingFraction: 0.85), value: isSelected)
    }
}
