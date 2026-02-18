//
//  BookmarkListView.swift
//  ScriptureScribe
//
//  Shows all saved bookmarks in a scrollable list.
//  Bookmarks are sorted by date (newest first) and can be deleted by swiping left.
//

import SwiftUI

struct BookmarkListView: View {

    @ObservedObject var bookmarksVM: BookmarksViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if bookmarksVM.bookmarks.isEmpty {
                    emptyState
                } else {
                    bookmarkList
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Bookmark List

    private var bookmarkList: some View {
        List {
            ForEach(sortedBookmarks) { bookmark in
                BookmarkRow(bookmark: bookmark)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete { offsets in
                for index in offsets {
                    bookmarksVM.removeBookmark(id: sortedBookmarks[index].id)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundStyle(themeManager.currentTheme.primary.opacity(0.5))
            Text("No Bookmarks Yet")
                .font(.headline)
                .foregroundStyle(themeManager.currentTheme.text)
            Text("While reading, tap the bookmark icon to save a chapter.")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Helpers

    private var sortedBookmarks: [Bookmark] {
        bookmarksVM.bookmarks.sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Bookmark Row

private struct BookmarkRow: View {

    let bookmark: Bookmark

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

            // Chapter name + date
            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.chapterReference)
                    .font(.headline)
                Text(bookmark.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
