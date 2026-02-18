//
//  BookSelectorRow.swift
//  ScriptureScribe
//
//  A horizontal scrollable row of Bible book names at the top of the reader.
//  The selected book is highlighted. A sort button lets the user switch between
//  canonical order (Genesis → Revelation) and A–Z order.
//

import SwiftUI

struct BookSelectorRow: View {

    @ObservedObject var vm: ReaderViewModel
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                // Sort toggle button (canonical ↔ alphabetical)
                Button {
                    withAnimation {
                        vm.bookSortOrder = vm.bookSortOrder == .canonical ? .alphabetical : .canonical
                    }
                } label: {
                    Image(systemName: vm.bookSortOrder == .canonical ? "list.number" : "textformat.abc")
                        .font(.footnote)
                        .foregroundStyle(themeManager.currentTheme.primary)
                        .frame(width: 36, height: 36)
                }
                .padding(.leading, 8)
                .help(vm.bookSortOrder == .canonical ? "Switch to A–Z order" : "Switch to Bible order")

                // Scrollable list of book names
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(vm.sortedBooks) { book in
                            BookChip(
                                book:       book,
                                isSelected: vm.selectedBook?.id == book.id,
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
                if vm.isLoadingBooks {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 8)
                }
            }
            .background(themeManager.currentTheme.surface)
            // Scroll the selected book into view automatically
            .onChange(of: vm.selectedBook?.id) { _, newID in
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
            .background(isSelected ? theme.primary : Color.clear)
            .foregroundStyle(isSelected ? Color.white : theme.text)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : theme.border, lineWidth: 1)
            )
    }
}
