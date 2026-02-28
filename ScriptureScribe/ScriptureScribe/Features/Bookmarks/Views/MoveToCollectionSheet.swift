//
//  MoveToCollectionSheet.swift
//  ScriptureScribe
//
//  Sheet for moving a bookmark to a different collection, or removing
//  it from its current collection.  Reuses the same "New collection"
//  inline creation flow as BookmarkPickerView.
//

import SwiftUI

struct MoveToCollectionSheet: View {

    let bookmark: Bookmark
    @EnvironmentObject var bookmarksVM: BookmarksViewModel
    @EnvironmentObject var authVM:      AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateGroup = false
    @State private var didMove         = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Drag handle
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                // ── Bookmark preview ─────────────────────────────────────
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: bookmark.colorHex))
                        .frame(width: 5, height: 44)
                    Text(bookmark.emoji)
                        .font(.title3)
                    Text(bookmark.chapterReference)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

                Divider()
                    .padding(.vertical, 14)

                // ── Header ───────────────────────────────────────────────
                HStack {
                    Text("Move to Collection")
                        .font(.headline)
                    Spacer()
                    Button("New collection") {
                        showCreateGroup = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                // ── Collection list ──────────────────────────────────────
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // "Remove from collection" row (only if bookmark is in a group)
                        if bookmark.groupId != nil {
                            Button {
                                moveBookmark(to: nil)
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(.systemGray5))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "folder.badge.minus")
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("Remove from collection")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            Divider().padding(.leading, 72)
                        }

                        ForEach(bookmarksVM.groups.sorted { $0.createdAt < $1.createdAt }) { group in
                            let isCurrent = bookmark.groupId == group.id
                            Button {
                                if !isCurrent { moveBookmark(to: group.id) }
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(hex: group.colorHex).opacity(0.18))
                                            .frame(width: 44, height: 44)
                                        Text(group.emoji)
                                            .font(.title3)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        let count = bookmarksVM.bookmarks.filter { $0.groupId == group.id }.count
                                        Text("\(count) bookmark\(count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isCurrent {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            Divider().padding(.leading, 72)
                        }
                    }
                }

                Spacer()
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupSheet(bookmarksVM: bookmarksVM)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Move Action

    private func moveBookmark(to groupId: String?) {
        bookmarksVM.assignBookmark(
            id:     bookmark.id,
            to:     groupId,
            userId: authVM.currentUserID
        )
        didMove = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { dismiss() }
    }
}
