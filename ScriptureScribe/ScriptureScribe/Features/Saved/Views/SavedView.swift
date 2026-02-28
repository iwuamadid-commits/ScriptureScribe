//
//  SavedView.swift
//  ScriptureScribe
//
//  The "Saved" main tab — three sub-tabs across the top:
//    • Bookmarks  — Instagram/TikTok-style collections grid; tap a tile to
//                   drill into the bookmarks inside that collection.
//    • Prayers    — prayers saved with the heart button in the Daily tab
//    • Devotionals — devotionals saved with the heart button in the Daily tab
//

import SwiftUI

// MARK: - Represents which collection the user tapped into

private enum CollectionDestination: Hashable {
    case all
    case group(id: String)
    case ungrouped
}

struct SavedView: View {

    @EnvironmentObject var themeManager:  ThemeManager
    @EnvironmentObject var authVM:        AuthViewModel
    @EnvironmentObject var bookmarksVM:   BookmarksViewModel
    @EnvironmentObject var savedVM:       SavedDevotionalsViewModel
    @EnvironmentObject var appNav:        AppNavigation

    @State private var selectedTab: SavedTab = .bookmarks
    @State private var movingBookmark: Bookmark?
    @State private var showManageGroups = false
    @State private var collectionPath: [CollectionDestination] = []

    enum SavedTab: Int, CaseIterable {
        case bookmarks, prayers, devotionals, affirmations
        var label: String {
            switch self {
            case .bookmarks:    return "Bookmarks"
            case .prayers:      return "Prayers"
            case .devotionals:  return "Devotionals"
            case .affirmations: return "Affirmations"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $collectionPath) {
            VStack(spacing: 0) {

                // ── Sub-tab pill strip ────────────────────────────────
                subTabStrip

                Divider()

                // ── Tab content ───────────────────────────────────────
                Group {
                    switch selectedTab {
                    case .bookmarks:
                        collectionsGrid
                    case .prayers:
                        devotionalItemList(items: savedVM.prayers, emptyMessage: "No saved prayers yet.\nTap the heart on a prayer in the Daily tab.")
                    case .devotionals:
                        devotionalItemList(items: savedVM.devotionals, emptyMessage: "No saved devotionals yet.\nTap the heart on a devotional in the Daily tab.")
                    case .affirmations:
                        devotionalItemList(items: savedVM.affirmations, emptyMessage: "No saved affirmations yet.\nTap the heart on an affirmation in the Daily tab.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if selectedTab == .bookmarks && collectionPath.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showManageGroups = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(item: $movingBookmark) { bookmark in
                MoveToCollectionSheet(bookmark: bookmark)
            }
            .sheet(isPresented: $showManageGroups) {
                ManageGroupsView(bookmarksVM: bookmarksVM)
            }
            .navigationDestination(for: CollectionDestination.self) { dest in
                collectionDetail(for: dest)
            }
        }
        .task(id: authVM.currentUserID) {
            if let uid = authVM.currentUserID {
                await savedVM.load(userId: uid)
            }
        }
    }

    // MARK: - Sub-tab Strip

    private var subTabStrip: some View {
        HStack(spacing: 0) {
            ForEach(SavedTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.label)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(
                                selectedTab == tab
                                    ? themeManager.currentTheme.primary
                                    : themeManager.currentTheme.textSecondary
                            )
                        Rectangle()
                            .fill(selectedTab == tab ? themeManager.currentTheme.primary : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
        .background(themeManager.currentTheme.surface)
    }

    // MARK: - Collections Grid (Instagram / TikTok style)

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var collectionsGrid: some View {
        Group {
            if bookmarksVM.bookmarks.isEmpty {
                emptyState(
                    icon:    "bookmark",
                    message: "No bookmarks yet.\nLong-press a verse while reading to save a bookmark."
                )
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {

                        // ── Full-width "All Saved" tile ─────────────────
                        Button {
                            collectionPath.append(.all)
                        } label: {
                            allSavedTile
                        }
                        .buttonStyle(.plain)

                        // ── 2-column grid of collection tiles ───────────
                        LazyVGrid(columns: gridColumns, spacing: 14) {
                            ForEach(allGroups) { group in
                                Button {
                                    collectionPath.append(.group(id: group.id))
                                } label: {
                                    collectionTile(
                                        emoji:    group.emoji,
                                        name:     group.name,
                                        colorHex: group.colorHex,
                                        count:    bookmarksForGroup(group.id).count
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            // "Ungrouped" tile (only if ungrouped bookmarks exist)
                            if !ungroupedBookmarks.isEmpty {
                                Button {
                                    collectionPath.append(.ungrouped)
                                } label: {
                                    collectionTile(
                                        emoji:    "📌",
                                        name:     "Ungrouped",
                                        colorHex: "7A8A9A",
                                        count:    ungroupedBookmarks.count
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    // MARK: - "All Saved" Tile

    private var allSavedTile: some View {
        HStack(spacing: 14) {
            Text("\u{1F516}")
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 2) {
                Text("All Saved")
                    .font(.headline)
                    .foregroundStyle(themeManager.currentTheme.text)
                Text("\(bookmarksVM.bookmarks.count) saved")
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.currentTheme.primary.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(themeManager.currentTheme.primary.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Collection Tile

    private func collectionTile(emoji: String, name: String, colorHex: String, count: Int) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(emoji)
                .font(.system(size: 40))
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.text)
                .lineLimit(1)
            Text("\(count) saved")
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: colorHex).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: colorHex).opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Collection Detail View

    @ViewBuilder
    private func collectionDetail(for destination: CollectionDestination) -> some View {
        let bookmarks: [Bookmark] = {
            switch destination {
            case .all:
                return bookmarksVM.bookmarks.sorted { $0.createdAt > $1.createdAt }
            case .group(let id):
                return bookmarksForGroup(id)
            case .ungrouped:
                return ungroupedBookmarks
            }
        }()

        let title: String = {
            switch destination {
            case .all:
                return "All Saved"
            case .group(let id):
                if let group = bookmarksVM.groups.first(where: { $0.id == id }) {
                    return group.emoji + " " + group.name
                }
                return "Collection"
            case .ungrouped:
                return "Ungrouped"
            }
        }()

        List {
            ForEach(bookmarks) { bookmark in
                Button {
                    navigateToBookmark(bookmark)
                } label: {
                    SavedBookmarkRow(bookmark: bookmark)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(themeManager.currentTheme.surface)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        bookmarksVM.removeBookmark(id: bookmark.id, userId: authVM.currentUserID)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        movingBookmark = bookmark
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(themeManager.currentTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Navigation

    private func navigateToBookmark(_ bookmark: Bookmark) {
        appNav.pendingVerseNumber    = bookmark.verseId.isEmpty ? nil : bookmark.verseId
        appNav.pendingVerseEndNumber = bookmark.verseIdEnd.isEmpty ? nil : bookmark.verseIdEnd
        appNav.pendingChapterId      = bookmark.chapterId
        appNav.selectedTab           = 0
    }

    private func navigateToDaily(entryDate: String) {
        appNav.pendingDailyDate = entryDate
        appNav.selectedTab      = 1
    }

    // MARK: - Bookmark Grouping Helpers

    /// All groups (even empty ones), sorted by creation date.
    private var allGroups: [BookmarkGroup] {
        bookmarksVM.groups.sorted { $0.createdAt < $1.createdAt }
    }

    /// Bookmarks in a specific group, sorted newest first.
    private func bookmarksForGroup(_ groupId: String) -> [Bookmark] {
        bookmarksVM.bookmarks
            .filter { $0.groupId == groupId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Bookmarks not in any group, sorted newest first.
    private var ungroupedBookmarks: [Bookmark] {
        bookmarksVM.bookmarks
            .filter { $0.groupId == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Prayers / Devotionals Tab

    private func devotionalItemList(items: [SavedDevotionalItem], emptyMessage: String) -> some View {
        Group {
            if items.isEmpty {
                emptyState(
                    icon: {
                        switch selectedTab {
                        case .prayers:      return "hands.clap"
                        case .affirmations: return "sparkles"
                        default:            return "book"
                        }
                    }(),
                    message: emptyMessage
                )
            } else {
                List {
                    ForEach(items) { item in
                        Button {
                            navigateToDaily(entryDate: item.entryDate)
                        } label: {
                            SavedItemRow(item: item)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(themeManager.currentTheme.surface)
                    }
                    .onDelete { offsets in
                        guard let uid = authVM.currentUserID else { return }
                        for index in offsets {
                            let item = items[index]
                            Task { await savedVM.delete(item, userId: uid) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(themeManager.currentTheme.background)
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(themeManager.currentTheme.primary.opacity(0.4))
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Bookmark Row

private struct SavedBookmarkRow: View {

    let bookmark: Bookmark
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: bookmark.colorHex))
                .frame(width: 6, height: 52)
            Text(bookmark.emoji)
                .font(.title2)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.chapterReference)
                    .font(.headline)
                    .foregroundStyle(themeManager.currentTheme.text)
                if !bookmark.verseText.isEmpty {
                    Text(bookmark.verseText)
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text(bookmark.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.textSecondary.opacity(0.5))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Saved Item Row (Prayer or Devotional)

private struct SavedItemRow: View {

    let item: SavedDevotionalItem
    @EnvironmentObject var themeManager: ThemeManager

    private var formattedDate: String {
        let f        = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        let iso      = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        iso.locale     = Locale(identifier: "en_US_POSIX")
        if let d = iso.date(from: item.entryDate) {
            return f.string(from: d)
        }
        return item.entryDate
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.verseReference)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.primary)
                    Spacer()
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                Text(item.content)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentTheme.text)
                    .lineLimit(3)
                    .lineSpacing(4)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.textSecondary.opacity(0.5))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SavedView()
        .environmentObject(ThemeManager())
        .environmentObject(AuthViewModel())
        .environmentObject(BookmarksViewModel())
        .environmentObject(SavedDevotionalsViewModel())
        .environmentObject(AppNavigation())
}
