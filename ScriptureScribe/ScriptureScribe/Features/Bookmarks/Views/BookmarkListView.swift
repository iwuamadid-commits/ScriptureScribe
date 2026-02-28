//
//  BookmarkListView.swift
//  ScriptureScribe
//
//  Shows all saved bookmarks in a scrollable list.
//  Bookmarks are sorted by date (newest first) and can be deleted by swiping left.
//  A row of group filter chips at the top lets the user narrow the list to a
//  specific group. A toolbar button opens ManageGroupsView to create or delete groups.
//

import SwiftUI

struct BookmarkListView: View {

    @ObservedObject var bookmarksVM: BookmarksViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    /// nil = show all;  "" = show ungrouped;  any group.id = filter to that group
    @State private var selectedGroupFilter: String? = nil
    @State private var showManageGroups = false

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
                    .swipeActions(edge: .leading) {
                        ShareLink(item: bookmarkShareText(bookmark)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(themeManager.currentTheme.primary)
                    }
                    .contextMenu {
                        ShareLink(item: bookmarkShareText(bookmark)) {
                            Label("Share Verse", systemImage: "square.and.arrow.up")
                        }
                    }
            }
            .onDelete { offsets in
                for index in offsets {
                    bookmarksVM.removeBookmark(id: filteredBookmarks[index].id)
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
