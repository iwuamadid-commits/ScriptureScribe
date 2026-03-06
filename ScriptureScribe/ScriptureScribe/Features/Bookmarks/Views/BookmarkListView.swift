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
            .sheet(item: $selectedBookmark) { bookmark in
                BookmarkDetailView(
                    bookmark: bookmark,
                    onNavigateToReader: { dismiss() }
                )
            }
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
                if bookmarksVM.bookmarks.contains(where: { $0.groupId == nil }) {
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
                BookmarkRow(bookmark: bookmark, group: group(for: bookmark))
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedBookmark = bookmark }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            bookmarksVM.removeBookmark(id: bookmark.id)
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
            return sorted.filter { $0.groupId == nil }
        } else {
            return sorted.filter { $0.groupId == filter }
        }
    }

    private func group(for bookmark: Bookmark) -> BookmarkGroup? {
        guard let gid = bookmark.groupId else { return nil }
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
    @Environment(\.dismiss) private var dismiss

    @State private var showMoveToCollection = false
    @State private var showImageComposer    = false
    @State private var showDeleteConfirm    = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    verseHeader

                    if !currentBookmark.verseText.isEmpty {
                        verseTextBlock
                    }

                    Divider()
                        .padding(.top, 4)

                    actionList
                }
                .padding(20)
            }
            .navigationTitle("Saved Verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                bookmarksVM.removeBookmark(id: bookmark.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove "\(currentBookmark.chapterReference)" from your bookmarks.")
        }
    }

    // MARK: - Live Bookmark

    /// Always reads the latest version of this bookmark from the VM so
    /// collection/group changes made in MoveToCollectionSheet are reflected immediately.
    private var currentBookmark: Bookmark {
        bookmarksVM.bookmarks.first { $0.id == bookmark.id } ?? bookmark
    }

    private var currentGroup: BookmarkGroup? {
        guard let gid = currentBookmark.groupId else { return nil }
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

    // MARK: - Action List

    private var actionList: some View {
        VStack(spacing: 0) {

            // Read
            actionRow(icon: "book.fill", label: "Read", color: themeManager.currentTheme.primary) {
                appNav.pendingChapterId      = currentBookmark.chapterId
                appNav.pendingVerseNumber    = currentBookmark.verseId.isEmpty    ? nil : currentBookmark.verseId
                appNav.pendingVerseEndNumber = currentBookmark.verseIdEnd.isEmpty ? nil : currentBookmark.verseIdEnd
                appNav.selectedTab           = 0
                onNavigateToReader()
            }
            Divider().padding(.leading, 52)

            // Share
            ShareLink(item: shareText) {
                rowContent(icon: "square.and.arrow.up", label: "Share", color: .blue)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 52)

            // Share as Image
            actionRow(icon: "photo", label: "Share as Image", color: .blue) {
                showImageComposer = true
            }
            Divider().padding(.leading, 52)

            // Copy
            actionRow(icon: "doc.on.doc", label: "Copy", color: .blue) {
                let text = currentBookmark.verseText.isEmpty
                    ? currentBookmark.chapterReference
                    : "\(currentBookmark.chapterReference)\n\"\(currentBookmark.verseText)\""
                UIPasteboard.general.string = text
                dismiss()
            }
            Divider().padding(.leading, 52)

            // Edit Collection
            actionRow(icon: "folder", label: "Edit Collection", color: .primary) {
                showMoveToCollection = true
            }
            Divider().padding(.leading, 52)

            // Delete
            actionRow(icon: "trash", label: "Delete", color: .red) {
                showDeleteConfirm = true
            }
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Row Helpers

    private func actionRow(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowContent(icon: icon, label: label, color: color)
        }
        .buttonStyle(.plain)
    }

    private func rowContent(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .font(.body)
                .foregroundStyle(color == .primary ? Color.primary : color)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
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
