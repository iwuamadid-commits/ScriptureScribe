//
//  MoveToCollectionSheet.swift
//  ScriptureScribe
//
//  Sheet for managing which collections a bookmark belongs to.
//  Supports multiple group membership — user can toggle groups on/off.
//  Also supports moving from one group to another when accessed from
//  a specific collection context.
//

import SwiftUI

struct MoveToCollectionSheet: View {

    let bookmark: Bookmark
    /// When set, the sheet is opened from a specific collection context (for "Move" action).
    var fromGroupId: String? = nil

    @EnvironmentObject var bookmarksVM: BookmarksViewModel
    @EnvironmentObject var authVM:      AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateGroup = false

    /// Live bookmark from the VM so changes are reflected immediately.
    private var currentBookmark: Bookmark {
        bookmarksVM.bookmarks.first { $0.id == bookmark.id } ?? bookmark
    }

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
                    Text(fromGroupId != nil ? "Move to Collection" : "Collections")
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
                        // "Remove from all collections" row
                        if !currentBookmark.groupIds.isEmpty {
                            Button {
                                bookmarksVM.setGroups(
                                    bookmarkId: bookmark.id,
                                    groupIds:   [],
                                    userId:     authVM.currentUserID
                                )
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { dismiss() }
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(.systemGray5))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "folder.badge.minus")
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("Remove from all collections")
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
                            let isMember = currentBookmark.groupIds.contains(group.id)
                            Button {
                                if let source = fromGroupId {
                                    // "Move" mode: remove from source, add to target
                                    bookmarksVM.moveBookmark(
                                        id:   bookmark.id,
                                        from: source,
                                        to:   group.id,
                                        userId: authVM.currentUserID
                                    )
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { dismiss() }
                                } else {
                                    // Toggle mode: add or remove from this group
                                    bookmarksVM.toggleGroup(
                                        bookmarkId: bookmark.id,
                                        groupId:    group.id,
                                        userId:     authVM.currentUserID
                                    )
                                }
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
                                        let count = bookmarksVM.bookmarks.filter { $0.groupIds.contains(group.id) }.count
                                        Text("\(count) bookmark\(count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isMember {
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

                // Done button
                if fromGroupId == nil {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupSheet(bookmarksVM: bookmarksVM)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
