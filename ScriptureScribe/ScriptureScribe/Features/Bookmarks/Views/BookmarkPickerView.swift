//
//  BookmarkPickerView.swift
//  ScriptureScribe
//
//  Instagram/TikTok-style "Save to Collection" bottom sheet.
//
//  • Shows a verse preview thumbnail at the top.
//  • Lists all existing groups with a "+" to instantly save into that group.
//  • "New collection" link opens CreateGroupSheet.
//  • "Save without a collection" saves the bookmark ungrouped.
//  • After saving, a checkmark replaces "+" for ~1 second, then the sheet dismisses.
//
//  BookmarksViewModel is read via @EnvironmentObject — so the group list
//  stays live even after the user creates a new collection from inside this sheet.
//

import SwiftUI

struct BookmarkPickerView: View {

    // Verse info passed in from ReaderView
    let chapterReference: String
    let verseText:        String
    let isAlreadyBookmarked: Bool

    // Callbacks
    let onSave:   (String, String, String?) -> Void  // (colorHex, emoji, groupId?)
    let onRemove: () -> Void

    @EnvironmentObject var bookmarksVM:    BookmarksViewModel
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var savedGroupId:    String? = nil  // which group just got the checkmark
    @State private var savedUngrouped               = false
    @State private var showCreateGroup              = false
    @State private var showImageComposer            = false
    @State private var showPaywall                  = false

    private var atCollectionLimit: Bool {
        !subscriptionVM.isPremium && bookmarksVM.groups.count >= PremiumLimits.maxFreeCollections
    }

    private var verseShareText: String {
        var parts: [String] = [chapterReference]
        if !verseText.isEmpty { parts.append("\"\(verseText)\"") }
        parts.append("Shared from Scripture Scribe")
        let encodedRef = chapterReference.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? chapterReference
        parts.append("scripturescribe://verse/\(encodedRef)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Drag handle
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                // ── Verse preview ──────────────────────────────────────────
                versePreview
                    .padding(.horizontal, 16)

                Divider()
                    .padding(.vertical, 14)

                // ── Collections header ─────────────────────────────────────
                HStack {
                    Text("Collections")
                        .font(.headline)
                    Spacer()
                    Button {
                        if atCollectionLimit {
                            showPaywall = true
                        } else {
                            showCreateGroup = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("New collection")
                            if atCollectionLimit {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                // ── Group list ─────────────────────────────────────────────
                if bookmarksVM.groups.isEmpty {
                    emptyCollectionsHint
                } else {
                    groupList
                }

                Divider()
                    .padding(.vertical, 10)

                // ── Footer actions ─────────────────────────────────────────
                VStack(spacing: 8) {
                    // Share buttons side by side
                    HStack(spacing: 12) {
                        ShareLink(item: verseShareText) {
                            Label("Share Verse", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)

                        Button { showImageComposer = true } label: {
                            Label("Share as Image", systemImage: "photo")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 16)

                    if isAlreadyBookmarked {
                        Button(role: .destructive) {
                            onRemove()
                            dismiss()
                        } label: {
                            Label("Remove Bookmark", systemImage: "bookmark.slash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, 16)
                    } else {
                        // Save without a collection
                        Button {
                            saveUngrouped()
                        } label: {
                            if savedUngrouped {
                                Label("Saved!", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Save without a collection")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                        .foregroundStyle(savedUngrouped ? .green : .secondary)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.fraction(0.65), .large])
        .presentationDragIndicator(.hidden) // we draw our own handle
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupSheet(bookmarksVM: bookmarksVM)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .fullScreenCover(isPresented: $showImageComposer) {
            VerseImageComposerView(
                verseText:      verseText,
                verseReference: chapterReference
            )
        }
    }

    // MARK: - Verse Preview

    private var versePreview: some View {
        HStack(spacing: 12) {
            // Colored stripe — uses first group color or a default gold
            let stripeColor = bookmarksVM.groups.first.map { Color(hex: $0.colorHex) }
                              ?? Color(hex: "F5C842")
            RoundedRectangle(cornerRadius: 4)
                .fill(stripeColor)
                .frame(width: 5, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(chapterReference)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !verseText.isEmpty {
                    Text(verseText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Group List

    private var groupList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(bookmarksVM.groups.sorted { $0.createdAt < $1.createdAt }) { group in
                    groupRow(group)
                    Divider().padding(.leading, 72)
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private func groupRow(_ group: BookmarkGroup) -> some View {
        let isSaved = savedGroupId == group.id
        return HStack(spacing: 14) {

            // Thumbnail square (like Instagram's collection cover)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: group.colorHex).opacity(0.18))
                    .frame(width: 52, height: 52)
                Text(group.emoji)
                    .font(.title2)
            }

            // Name + "Private" label
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.subheadline.weight(.medium))
                Text("Private")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // "+" / checkmark button
            Button {
                saveToGroup(group)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(isSaved ? Color.green : Color(.systemGray3), lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                    Image(systemName: isSaved ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSaved ? .green : .primary)
                }
            }
            .disabled(isSaved)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { saveToGroup(group) }
    }

    // MARK: - Empty Hint

    private var emptyCollectionsHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No collections yet")
                .font(.subheadline.weight(.medium))
            Text("Tap \"New collection\" to create one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Save Actions

    private func saveToGroup(_ group: BookmarkGroup) {
        guard savedGroupId == nil && !savedUngrouped else { return }
        onSave(group.colorHex, group.emoji, group.id)
        withAnimation(.spring(response: 0.2)) { savedGroupId = group.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
    }

    private func saveUngrouped() {
        guard savedGroupId == nil && !savedUngrouped else { return }
        onSave("F5C842", "🔖", nil)
        withAnimation(.spring(response: 0.2)) { savedUngrouped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
    }
}
