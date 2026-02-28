//
//  BookSelectorRow.swift
//  ScriptureScribe
//
//  A horizontal scrollable row of Bible book names at the top of the reader.
//  The selected book is highlighted with a pill that slides to the new selection.
//  A sort button lets the user switch between canonical order (Genesis → Revelation)
//  and A–Z order.
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
    @EnvironmentObject var themeManager: ThemeManager

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
                        .font(.footnote)
                        .foregroundStyle(themeManager.currentTheme.primary)
                        .frame(width: 36, height: 36)
                }
                .padding(.leading, 8)
                .help(bookSortOrder == .canonical ? "Switch to A–Z order" : "Switch to Bible order")

                // Scrollable list of book names
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(sortedBooks) { book in
                            BookChip(
                                book:       book,
                                isSelected: selectedBookId == book.id,
                                theme:      themeManager.currentTheme
                            )
                            .id(book.id)
                            .onTapGesture {
                                Task { await vm.selectBook(book) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
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
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }
}

// MARK: - Single Book Chip

private struct BookChip: View {

    let book:       BibleBook
    let isSelected: Bool
    let theme:      any AppTheme

    var body: some View {
        Text(book.name)
            .font(.footnote.weight(isSelected ? .bold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 10)
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
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}
