//
//  BookmarkListView.swift
//  ScriptureScribe
//
//  Shows all saved bookmarks in a scrollable list.
//  Bookmarks are sorted by date (newest first) and can be deleted by swiping left.
//  A row of group filter chips at the top lets the user narrow the list to a
//  specific group. A toolbar button opens ManageGroupsView to create or delete groups.
//
//  Tapping a row opens BookmarkDetailView — a popup sheet that shows the saved
//  verse text and offers actions: Read, Share, Share as Image, Copy, Edit, Delete.
//

import SwiftUI

struct BookmarkListView: View {

    @ObservedObject var bookmarksVM: BookmarksViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    /// nil = show all;  "" = show ungrouped;  any group.id = filter to that group
    @State private var selectedGroupFilter: String? = nil
    @State private var showManageGroups = false
    @State private var selectedBookmark: Bookmark? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Group filter strip (only shown when groups exist)
                if !bookmarksVM.groups.isEmpty {
                    groupFilterStrip
                    Divider()
                }

                Group {
                    if filteredBookmarks.isEmpty {
                        emptyState
                    } else {
                        bookmarkList
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showManageGroups = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .help("Manage Groups")
                }
            }
            .sheet(isPresented: $showManageGroups) {
                ManageGroupsView(bookmarksVM: bookmarksVM)
            }
        }
        // Kept at NavigationStack level (not chained on the VStack) so it
        // doesn't conflict with the showManageGroups sheet above.
        .sheet(item: $selectedBookmark) { bookmark in
            BookmarkDetailView(
                bookmark: bookmark,
                onNavigateToReader: { dismiss() }
            )
        }
    }

    // MARK: - Group Filter Strip

    private var groupFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                filterChip(label: "All", colorHex: nil, isSelected: selectedGroupFilter == nil) {
                    selectedGroupFilter = nil
                }

                // Each group chip
                ForEach(bookmarksVM.groups.sorted { $0.createdAt < $1.createdAt }) { group in
                    filterChip(
                        label:     group.emoji + " " + group.name,
                        colorHex:  group.colorHex,
                        isSelected: selectedGroupFilter == group.id
                    ) {
                        selectedGroupFilter = group.id
                    }
                }

                // "Ungrouped" chip (only if there are ungrouped bookmarks)
                if bookmarksVM.bookmarks.contains(where: { $0.groupIds.isEmpty }) {
                    filterChip(label: "Ungrouped", colorHex: "7A8A9A",
                               isSelected: selectedGroupFilter == "") {
                        selectedGroupFilter = ""
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func filterChip(
        label: String,
        colorHex: String?,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        let accentColor = colorHex.map { Color(hex: $0) } ?? themeManager.currentTheme.primary
        Button(action: onTap) {
            Text(label)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(accentColor)
                            .opacity(isSelected ? 1 : 0)
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(accentColor, lineWidth: 1.5)
                            .opacity(isSelected ? 0 : 0.7)
                    }
                }
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
        }
    }

    // MARK: - Bookmark List

    private var bookmarkList: some View {
        List {
            ForEach(filteredBookmarks) { bookmark in
                Button { selectedBookmark = bookmark } label: {
                    BookmarkRow(bookmark: bookmark, group: group(for: bookmark))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            bookmarksVM.removeBookmark(id: bookmark.id, userId: authVM.currentUserID)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        ShareLink(item: bookmarkShareText(bookmark)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(themeManager.currentTheme.primary)
                    }
            }
        }
        .listStyle(.plain)
    }

    private func bookmarkShareText(_ bookmark: Bookmark) -> String {
        var parts: [String] = [bookmark.chapterReference]
        if !bookmark.verseText.isEmpty {
            parts.append("\"\(bookmark.verseText)\"")
        }
        parts.append("Shared from Scripture Scribe")
        parts.append("scripturescribe://verse/\(bookmark.chapterId)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedGroupFilter != nil ? "bookmark.slash" : "bookmark")
                .font(.system(size: 48))
                .foregroundStyle(themeManager.currentTheme.primary.opacity(0.5))
            Text(selectedGroupFilter != nil ? "No Bookmarks in This Group" : "No Bookmarks Yet")
                .font(.headline)
                .foregroundStyle(themeManager.currentTheme.text)
            Text(selectedGroupFilter != nil
                 ? "Long-press a verse and assign it to this group."
                 : "While reading, long-press a verse to save a bookmark.")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Helpers

    private var filteredBookmarks: [Bookmark] {
        let sorted = bookmarksVM.bookmarks.sorted { $0.createdAt > $1.createdAt }
        guard let filter = selectedGroupFilter else { return sorted }
        if filter.isEmpty {
            // Show ungrouped
            return sorted.filter { $0.groupIds.isEmpty }
        } else {
            return sorted.filter { $0.groupIds.contains(filter) }
        }
    }

    private func group(for bookmark: Bookmark) -> BookmarkGroup? {
        guard let gid = bookmark.groupIds.first else { return nil }
        return bookmarksVM.groups.first { $0.id == gid }
    }
}

// MARK: - Bookmark Row

private struct BookmarkRow: View {

    let bookmark: Bookmark
    let group:    BookmarkGroup?

    var body: some View {
        HStack(spacing: 14) {

            // Colored ribbon strip on the left
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: bookmark.colorHex))
                .frame(width: 6, height: 52)

            // Emoji
            Text(bookmark.emoji)
                .font(.title2)
                .frame(width: 36)

            // Chapter name + group badge + date
            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.chapterReference)
                    .font(.headline)

                HStack(spacing: 6) {
                    if let group {
                        HStack(spacing: 3) {
                            Text(group.emoji)
                            Text(group.name)
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: group.colorHex).opacity(0.2),
                                    in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Color(hex: group.colorHex))
                    }

                    Text(bookmark.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bookmark Detail View

/// Full-screen popup sheet that appears when the user taps a bookmark row.
/// Shows the saved verse text and action buttons: Read, Share, Share as Image, Copy, Edit, Delete.
struct BookmarkDetailView: View {

    /// Snapshot of the bookmark at open time — use `currentBookmark` for live-updated reads.
    let bookmark: Bookmark
    /// Called after "Read" so the parent BookmarkListView can dismiss itself too.
    let onNavigateToReader: () -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var appNav:       AppNavigation
    @EnvironmentObject var bookmarksVM:  BookmarksViewModel
    @EnvironmentObject var authVM:       AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showMoveToCollection = false
    @State private var showImageComposer    = false
    @State private var showDeleteConfirm    = false
    @State private var showEditBookmark     = false
    @State private var showEditVerses       = false
    @State private var detent: PresentationDetent = .large

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    verseHeader

                    if !currentBookmark.verseText.isEmpty {
                        verseTextBlock
                    }
                }
                .padding(20)
            }
            .navigationTitle("Saved Verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            appNav.pendingChapterId      = currentBookmark.chapterId
                            let nums = currentBookmark.resolvedVerseNumbers
                            appNav.pendingVerseNumbers   = nums.isEmpty ? nil : nums
                            appNav.pendingVerseNumber    = nums.first
                            appNav.pendingVerseEndNumber = nil
                            appNav.selectedTab           = 0
                            dismiss()
                            onNavigateToReader()
                        } label: {
                            Label("Read", systemImage: "book.fill")
                        }

                        ShareLink(item: shareText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            showImageComposer = true
                        } label: {
                            Label("Share as Image", systemImage: "photo")
                        }

                        Button {
                            let text = currentBookmark.verseText.isEmpty
                                ? currentBookmark.chapterReference
                                : "\(currentBookmark.chapterReference)\n\"\(currentBookmark.verseText)\""
                            UIPasteboard.general.string = text
                            dismiss()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        Button {
                            showEditVerses = true
                        } label: {
                            Label("Edit Verses", systemImage: "text.badge.plus")
                        }

                        Button {
                            showEditBookmark = true
                        } label: {
                            Label("Edit Bookmark", systemImage: "pencil")
                        }

                        Button {
                            showMoveToCollection = true
                        } label: {
                            Label("Edit Collection", systemImage: "folder")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                    }
                    .accessibilityLabel("More options")
                }
            }
        }
        .presentationDetents([.large, .medium], selection: $detent)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showEditVerses) {
            EditVerseRangeSheet(bookmark: currentBookmark)
        }
        .sheet(isPresented: $showEditBookmark) {
            EditBookmarkSheet(bookmark: currentBookmark)
        }
        .sheet(isPresented: $showMoveToCollection) {
            MoveToCollectionSheet(bookmark: currentBookmark)
        }
        .fullScreenCover(isPresented: $showImageComposer) {
            VerseImageComposerView(
                verseText:      currentBookmark.verseText,
                verseReference: currentBookmark.chapterReference
            )
        }
        .confirmationDialog(
            "Delete this bookmark?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                bookmarksVM.removeBookmark(id: bookmark.id, userId: authVM.currentUserID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove \"\(currentBookmark.chapterReference)\" from your bookmarks.")
        }
    }

    // MARK: - Live Bookmark

    /// Always reads the latest version of this bookmark from the VM so
    /// collection/group changes made in MoveToCollectionSheet are reflected immediately.
    private var currentBookmark: Bookmark {
        bookmarksVM.bookmarks.first { $0.id == bookmark.id } ?? bookmark
    }

    private var currentGroup: BookmarkGroup? {
        guard let gid = currentBookmark.groupIds.first else { return nil }
        return bookmarksVM.groups.first { $0.id == gid }
    }

    // MARK: - Verse Header

    private var verseHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: currentBookmark.colorHex))
                .frame(width: 6, height: 60)

            VStack(alignment: .leading, spacing: 6) {
                Text(currentBookmark.emoji)
                    .font(.title2)
                Text(currentBookmark.chapterReference)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeManager.currentTheme.text)

                if let group = currentGroup {
                    HStack(spacing: 3) {
                        Text(group.emoji)
                        Text(group.name)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color(hex: group.colorHex).opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .foregroundStyle(Color(hex: group.colorHex))
                }
            }

            Spacer()
        }
    }

    // MARK: - Verse Text Block

    private var verseTextBlock: some View {
        Text(currentBookmark.verseText)
            .font(.body)
            .foregroundStyle(themeManager.currentTheme.text)
            .lineSpacing(6)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Color(hex: currentBookmark.colorHex).opacity(0.5),
                        lineWidth: 1.5
                    )
            )
    }

    // MARK: - Share Text

    private var shareText: String {
        var parts: [String] = [currentBookmark.chapterReference]
        if !currentBookmark.verseText.isEmpty {
            parts.append("\"\(currentBookmark.verseText)\"")
        }
        parts.append("Shared from Scripture Scribe")
        parts.append("scripturescribe://verse/\(currentBookmark.chapterId)")
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Edit Bookmark Sheet

/// Lets the user change a bookmark's emoji and color.
struct EditBookmarkSheet: View {

    let bookmark: Bookmark

    @EnvironmentObject var bookmarksVM: BookmarksViewModel
    @EnvironmentObject var authVM:      AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedColor: String
    @State private var selectedEmoji: String

    init(bookmark: Bookmark) {
        self.bookmark     = bookmark
        _selectedColor    = State(initialValue: bookmark.colorHex)
        _selectedEmoji    = State(initialValue: bookmark.emoji)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {

                // Preview
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: selectedColor))
                        .frame(width: 6, height: 52)
                    Text(selectedEmoji)
                        .font(.title2)
                    Text(bookmark.chapterReference)
                        .font(.headline)
                    Spacer()
                }
                .padding(14)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))

                // Color picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("Color")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Bookmark.presetColors, id: \.hex) { preset in
                                let isSelected = selectedColor == preset.hex
                                Circle()
                                    .fill(Color(hex: preset.hex))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary.opacity(isSelected ? 0.9 : 0),
                                                    lineWidth: 2.5)
                                            .padding(3)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
                                            .padding(4)
                                    )
                                    .onTapGesture { selectedColor = preset.hex }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Emoji picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("Emoji")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Bookmark.presetEmojis, id: \.self) { emoji in
                            Text(emoji)
                                .font(.title2)
                                .frame(width: 52, height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedEmoji == emoji
                                              ? Color(hex: selectedColor).opacity(0.2)
                                              : Color(.systemGray6))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(hex: selectedColor),
                                                lineWidth: selectedEmoji == emoji ? 2 : 0)
                                )
                                .onTapGesture { selectedEmoji = emoji }
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Edit Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        bookmarksVM.updateBookmark(
                            id:       bookmark.id,
                            colorHex: selectedColor,
                            emoji:    selectedEmoji,
                            userId:   authVM.currentUserID
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Edit Verse Range Sheet

/// Lets the user add or remove verses from a bookmark by adjusting the start/end verse range.
/// Fetches the chapter from the API so the preview shows live verse text.
struct EditVerseRangeSheet: View {

    let bookmark: Bookmark

    @EnvironmentObject var bookmarksVM: BookmarksViewModel
    @EnvironmentObject var authVM:      AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var verses:      [ParsedVerse] = []
    @State private var chapterName: String = ""
    @State private var isLoading:   Bool   = true
    @State private var startNum:    Int    = 1
    @State private var endNum:      Int    = 1

    private let api = BibleAPIService()

    // Verses with real numbers only (skip "§" section-heading pseudo-verses)
    private var numberedVerses: [ParsedVerse] {
        verses.filter { $0.number != "§" }
    }

    private var maxVerseNum: Int {
        numberedVerses.compactMap { Int($0.number) }.max() ?? 1
    }

    private var selectedVerses: [ParsedVerse] {
        numberedVerses.filter {
            guard let n = Int($0.number) else { return false }
            return n >= startNum && n <= endNum
        }
    }

    private var previewText: String {
        selectedVerses.map { v in
            let text = v.segments.map { $0.text }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "[\(v.number)] \(text)"
        }.joined(separator: "\n\n")
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Loading chapter…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .navigationTitle("Edit Verses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(isLoading)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await loadChapter() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Range steppers
                VStack(spacing: 0) {
                    HStack {
                        Text("From verse")
                            .font(.body)
                        Spacer()
                        Stepper(value: $startNum, in: 1...maxVerseNum) {
                            Text("\(startNum)")
                                .font(.body.weight(.semibold))
                                .frame(minWidth: 24, alignment: .trailing)
                        }
                        .onChange(of: startNum) { _, newVal in
                            if endNum < newVal { endNum = newVal }
                        }
                    }
                    .padding(16)

                    Divider().padding(.leading, 16)

                    HStack {
                        Text("To verse")
                            .font(.body)
                        Spacer()
                        Stepper(value: $endNum, in: startNum...maxVerseNum) {
                            Text("\(endNum)")
                                .font(.body.weight(.semibold))
                                .frame(minWidth: 24, alignment: .trailing)
                        }
                    }
                    .padding(16)
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))

                // Live preview
                VStack(alignment: .leading, spacing: 10) {
                    Text("Preview")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(previewText.isEmpty ? "No verses selected" : previewText)
                        .font(.body)
                        .foregroundStyle(
                            previewText.isEmpty
                                ? themeManager.currentTheme.textSecondary
                                : themeManager.currentTheme.text
                        )
                        .lineSpacing(5)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(.systemGray6),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    Color(hex: bookmark.colorHex).opacity(0.4),
                                    lineWidth: 1.5
                                )
                        )
                }
            }
            .padding(20)
        }
    }

    private func loadChapter() async {
        do {
            let content = try await api.fetchChapterContent(
                bibleId:   bookmark.bibleId,
                chapterId: bookmark.chapterId
            )
            verses      = content.parsedVerses
            chapterName = content.reference

            // Seed steppers from the existing bookmark range
            let rawStart = Int(bookmark.verseId) ?? 1
            let rawEnd   = bookmark.verseIdEnd.isEmpty
                           ? rawStart
                           : (Int(bookmark.verseIdEnd) ?? rawStart)
            let cap = numberedVerses.compactMap { Int($0.number) }.max() ?? 1
            startNum = min(max(rawStart, 1), cap)
            endNum   = min(max(rawEnd,   startNum), cap)
        } catch {
            // Fallback: seed from bookmark data, stepper shows 1 verse
            startNum = Int(bookmark.verseId) ?? 1
            endNum   = bookmark.verseIdEnd.isEmpty ? startNum : (Int(bookmark.verseIdEnd) ?? startNum)
        }
        isLoading = false
    }

    private func save() {
        let startId = "\(startNum)"
        let endId   = endNum == startNum ? "" : "\(endNum)"

        let text = selectedVerses
            .map { $0.segments.map { $0.text }.joined() }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let ref: String
        if endId.isEmpty {
            ref = "\(chapterName): \(startId)"
        } else {
            ref = "\(chapterName): \(startId)-\(endId)"
        }

        bookmarksVM.updateBookmarkVerses(
            id:               bookmark.id,
            verseId:          startId,
            verseIdEnd:       endId,
            verseText:        text,
            chapterReference: ref,
            userId:           authVM.currentUserID
        )
        dismiss()
    }
}
