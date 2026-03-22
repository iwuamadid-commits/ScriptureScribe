//
//  BookBrowserView.swift
//  ScriptureScribe
//
//  Book & chapter browser presented as a sheet. Shows all 66 books organized by
//  testament (Old Testament / New Testament). Tapping a book expands a 5-column
//  grid of chapter numbers. Tapping a chapter navigates there and dismisses.
//
//  Triggered by tapping the currently selected book chip in BookSelectorRow.
//

import SwiftUI

struct BookBrowserView: View {

    let books:             [BibleBook]
    let selectedBookId:    String?
    let selectedChapterId: String?
    let vm:                ReaderViewModel
    var scrollToChapter:   Bool = false
    var annotationVM:      AnnotationViewModel? = nil
    var notesVM:           NotesViewModel?      = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    @State private var expandedBookId:    String?         = nil
    @State private var expandedChapters:  [BibleChapter]  = []
    @State private var isLoadingChapters                  = false
    @State private var searchText:        String          = ""

    private var isSearching: Bool { !searchText.isEmpty }

    private var filteredBooks: [BibleBook] {
        guard isSearching else { return books }
        let query = searchText.lowercased()
        return books.filter {
            $0.name.lowercased().hasPrefix(query) ||
            $0.abbreviation.lowercased().hasPrefix(query) ||
            $0.nameLong.lowercased().contains(query)
        }
    }

    private var otBooks: [BibleBook] { filteredBooks.filter { !$0.isNewTestament } }
    private var ntBooks: [BibleBook] { filteredBooks.filter {  $0.isNewTestament } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    // Pinned search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.subheadline)
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                        TextField("Search books", text: $searchText)
                            .font(.subheadline)
                            .foregroundStyle(themeManager.currentTheme.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if isSearching {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(themeManager.currentTheme.surface)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(themeManager.currentTheme.background)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        if filteredBooks.isEmpty {
                            Text("No books found")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            // Old Testament
                            if !otBooks.isEmpty {
                                testamentSection(title: "Old Testament", books: otBooks, proxy: proxy)
                            }

                            // Divider between testaments (only when both are visible)
                            if !otBooks.isEmpty && !ntBooks.isEmpty {
                                HStack(spacing: 10) {
                                    Rectangle().frame(height: 1)
                                    Text("New Testament")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                    Rectangle().frame(height: 1)
                                }
                                .foregroundStyle(themeManager.currentTheme.primary.opacity(0.3))
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                .padding(.bottom, 4)
                            }

                            // New Testament
                            if !ntBooks.isEmpty {
                                testamentSection(title: otBooks.isEmpty ? "New Testament" : nil, books: ntBooks, proxy: proxy)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollContentBackground(.hidden)
                .background(themeManager.currentTheme.background)
                .onAppear {
                    if let currentBookId = selectedBookId {
                        expandedBookId = currentBookId
                        Task {
                            if let book = books.first(where: { $0.id == currentBookId }) {
                                expandedChapters = await vm.fetchChapters(for: book)
                            }

                            // Instantly position near the book while the sheet is still
                            // animating in — the user won't see this jump.
                            proxy.scrollTo(currentBookId, anchor: .top)

                            // Wait for the sheet presentation to finish.
                            try? await Task.sleep(for: .milliseconds(500))

                            if scrollToChapter, let chapterId = selectedChapterId {
                                // Smooth scroll from the book row down to the chapter cell.
                                withAnimation(.spring(response: 1.0, dampingFraction: 0.85)) {
                                    proxy.scrollTo(chapterId, anchor: .center)
                                }
                            } else {
                                // Already positioned at the book — just ensure it's visible.
                                withAnimation(.spring(response: 1.0, dampingFraction: 0.85)) {
                                    proxy.scrollTo(currentBookId, anchor: .top)
                                }
                            }
                        }
                    }
                }
                } // VStack (search bar + scroll)
            }
            .navigationTitle("Select a Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
        }
    }

    // MARK: - Testament Section

    @ViewBuilder
    private func testamentSection(title: String?, books: [BibleBook], proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            }

            ForEach(books) { book in
                bookRow(book, proxy: proxy)
            }
        }
    }

    // MARK: - Book Row

    @ViewBuilder
    private func bookRow(_ book: BibleBook, proxy: ScrollViewProxy) -> some View {
        let isExpanded = expandedBookId == book.id
        let isCurrent  = selectedBookId == book.id

        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleBook(book, proxy: proxy)
            } label: {
                HStack(spacing: 0) {
                    // Current book indicator
                    if isCurrent {
                        Circle()
                            .fill(themeManager.currentTheme.primary)
                            .frame(width: 6, height: 6)
                            .padding(.trailing, 10)
                    }

                    Text(book.name)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent
                                         ? themeManager.currentTheme.primary
                                         : themeManager.currentTheme.text)

                    Spacer()

                    if isLoadingChapters && expandedBookId == book.id {
                        ProgressView()
                            .scaleEffect(0.5)
                            .padding(.trailing, 4)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.textSecondary.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .id(book.id)

            // Expanded chapter grid
            if isExpanded && !expandedChapters.isEmpty {
                chapterGrid(for: book)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Subtle divider
            Divider()
                .padding(.leading, isCurrent ? 36 : 20)
        }
    }

    // MARK: - Chapter Grid

    private func chapterGrid(for book: BibleBook) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(expandedChapters) { chapter in
                let isCurrentChapter = chapter.id == selectedChapterId
                let hasAnnotation = (annotationVM?.hasAnnotation(for: chapter.id) ?? false) ||
                                    !(notesVM?.notes(for: chapter.id).isEmpty ?? true)
                Button {
                    dismiss()
                    Task {
                        await vm.selectBookAndChapter(bookId: book.id, chapterId: chapter.id)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(chapter.number)
                            .font(.subheadline.weight(isCurrentChapter ? .bold : .regular))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundStyle(isCurrentChapter ? Color.white : themeManager.currentTheme.text)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isCurrentChapter
                                          ? themeManager.currentTheme.primary
                                          : themeManager.currentTheme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(themeManager.currentTheme.border,
                                            lineWidth: isCurrentChapter ? 0 : 1)
                            )

                        // Annotation indicator dot
                        Circle()
                            .fill(themeManager.currentTheme.primary)
                            .frame(width: 5, height: 5)
                            .opacity(hasAnnotation ? 1 : 0)
                    }
                }
                .buttonStyle(.plain)
                .id(chapter.id)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    // MARK: - Toggle Book Expansion

    private func toggleBook(_ book: BibleBook, proxy: ScrollViewProxy) {
        if expandedBookId == book.id {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                expandedBookId = nil
                expandedChapters = []
            }
        } else {
            Task {
                isLoadingChapters = true
                expandedChapters = []
                expandedBookId = book.id
                let chapters = await vm.fetchChapters(for: book)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expandedChapters = chapters
                    isLoadingChapters = false
                }
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.spring(response: 1.0, dampingFraction: 0.85)) {
                    proxy.scrollTo(book.id, anchor: .top)
                }
            }
        }
    }
}
