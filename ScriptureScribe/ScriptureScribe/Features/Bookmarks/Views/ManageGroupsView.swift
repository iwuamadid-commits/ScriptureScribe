//
//  ManageGroupsView.swift
//  ScriptureScribe
//
//  Lets the user create, view, edit, and delete bookmark groups.
//
//  Groups have:
//    • A name they type themselves
//    • A ribbon color  (same 8 presets used for bookmarks)
//    • An emoji icon   (any emoji from the full Apple emoji keyboard)
//
//  The emoji picker uses a UITextField subclass that forces iOS to open the
//  emoji keyboard automatically — giving the user access to every emoji Apple
//  supports, not just a curated list.
//

import SwiftUI
import UIKit

struct ManageGroupsView: View {

    @ObservedObject var bookmarksVM: BookmarksViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateSheet = false
    @State private var editingGroup: BookmarkGroup?
    @State private var showPaywall = false

    private var atCollectionLimit: Bool {
        !subscriptionVM.isPremium && bookmarksVM.groups.count >= PremiumLimits.maxFreeCollections
    }

    var body: some View {
        NavigationStack {
            Group {
                if bookmarksVM.groups.isEmpty {
                    emptyState
                } else {
                    groupList
                }
            }
            .navigationTitle("Bookmark Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if atCollectionLimit {
                            showPaywall = true
                        } else {
                            showCreateSheet = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            if atCollectionLimit {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateGroupSheet(bookmarksVM: bookmarksVM)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(item: $editingGroup) { group in
                EditGroupSheet(bookmarksVM: bookmarksVM, group: group)
            }
        }
    }

    // MARK: - Group List

    private var groupList: some View {
        List {
            ForEach(sortedGroups) { group in
                Button {
                    editingGroup = group
                } label: {
                    HStack(spacing: 14) {
                        // Colored ribbon strip
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: group.colorHex))
                            .frame(width: 6, height: 44)

                        // Emoji
                        Text(group.emoji)
                            .font(.title2)
                            .frame(width: 36)

                        // Name + count
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.headline)
                                .foregroundStyle(themeManager.currentTheme.text)
                            let count = bookmarksVM.bookmarks.filter { $0.groupIds.contains(group.id) }.count
                            Text("\(count) bookmark\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    bookmarksVM.deleteGroup(id: sortedGroups[index].id)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(themeManager.currentTheme.primary.opacity(0.5))
            Text("No Groups Yet")
                .font(.headline)
                .foregroundStyle(themeManager.currentTheme.text)
            Text("Tap + to create your first bookmark group.")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                if atCollectionLimit {
                    showPaywall = true
                } else {
                    showCreateSheet = true
                }
            } label: {
                Label("Create Group", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private var sortedGroups: [BookmarkGroup] {
        bookmarksVM.groups.sorted { $0.createdAt < $1.createdAt }
    }
}

// MARK: - Create Group Sheet

struct CreateGroupSheet: View {

    @ObservedObject var bookmarksVM: BookmarksViewModel
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var groupName:     String = ""
    @State private var groupColorHex: String = Bookmark.presetColors[0].hex
    @State private var groupEmoji:    String = "📖"
    @State private var showPaywall           = false

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // ── Emoji preview + picker ──────────────────────────────
                    VStack(spacing: 8) {
                        Text("Group Icon")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)

                        // Large emoji display that IS the text field
                        EmojiTextField(text: $groupEmoji)
                            .frame(height: 72)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(hex: groupColorHex).opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color(hex: groupColorHex).opacity(0.4), lineWidth: 1.5)
                                    )
                            )
                            .padding(.horizontal, 20)

                        Text("Tap the box above to open your emoji keyboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    // ── Group name ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Group Name")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        TextField("e.g. Prayer Verses, Favorites…", text: $groupName)
                            .padding(12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                    }

                    // ── Ribbon color ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ribbon Color")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Bookmark.presetColors, id: \.hex) { option in
                                    let isSelected = groupColorHex == option.hex
                                    Button { groupColorHex = option.hex } label: {
                                        Circle()
                                            .fill(Color(hex: option.hex))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Circle()
                                                    .stroke(.white, lineWidth: isSelected ? 3 : 0)
                                                    .padding(3)
                                            )
                                            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                                    }
                                    .accessibilityLabel(option.name)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // ── Live preview ────────────────────────────────────────
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: groupColorHex))
                            .frame(width: 8, height: 52)
                        VStack(alignment: .leading) {
                            Text(groupEmoji + "  " + (groupName.isEmpty ? "Group Name" : groupName))
                                .font(.headline)
                            Text("Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // ── Create button ───────────────────────────────────────
                    Button {
                        bookmarksVM.addGroup(
                            name:     groupName,
                            colorHex: groupColorHex,
                            emoji:    groupEmoji
                        )
                        dismiss()
                    } label: {
                        Label("Create Group", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .padding(.top, 8)
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

// MARK: - Edit Group Sheet

struct EditGroupSheet: View {

    @ObservedObject var bookmarksVM: BookmarksViewModel
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    let group: BookmarkGroup
    @Environment(\.dismiss) private var dismiss

    @State private var groupName:     String = ""
    @State private var groupColorHex: String = ""
    @State private var groupEmoji:    String = ""
    @State private var showPaywall           = false

    private var canSave: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // ── Emoji preview + picker ──────────────────────────────
                    VStack(spacing: 8) {
                        Text("Group Icon")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)

                        EmojiTextField(text: $groupEmoji)
                            .frame(height: 72)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(hex: groupColorHex).opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color(hex: groupColorHex).opacity(0.4), lineWidth: 1.5)
                                    )
                            )
                            .padding(.horizontal, 20)

                        Text("Tap the box above to open your emoji keyboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    // ── Group name ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Group Name")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        TextField("e.g. Prayer Verses, Favorites…", text: $groupName)
                            .padding(12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                    }

                    // ── Ribbon color ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ribbon Color")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Bookmark.presetColors, id: \.hex) { option in
                                    let isSelected = groupColorHex == option.hex
                                    Button { groupColorHex = option.hex } label: {
                                        Circle()
                                            .fill(Color(hex: option.hex))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Circle()
                                                    .stroke(.white, lineWidth: isSelected ? 3 : 0)
                                                    .padding(3)
                                            )
                                            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                                    }
                                    .accessibilityLabel(option.name)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // ── Live preview ────────────────────────────────────────
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: groupColorHex))
                            .frame(width: 8, height: 52)
                        VStack(alignment: .leading) {
                            Text(groupEmoji + "  " + (groupName.isEmpty ? "Group Name" : groupName))
                                .font(.headline)
                            Text("Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // ── Save button ─────────────────────────────────────────
                    Button {
                        bookmarksVM.updateGroup(
                            id:       group.id,
                            name:     groupName,
                            colorHex: groupColorHex,
                            emoji:    groupEmoji
                        )
                        dismiss()
                    } label: {
                        Label("Save Changes", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onAppear {
            groupName     = group.name
            groupColorHex = group.colorHex
            groupEmoji    = group.emoji
        }
    }
}

// MARK: - Emoji Text Field (UIViewRepresentable)
//
// A UITextField subclass that overrides textInputMode to force the emoji keyboard.
// This gives the user access to Apple's complete emoji set — every category,
// skin-tone modifiers, and all compound sequences.

struct EmojiTextField: UIViewRepresentable {

    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EmojiUITextField {
        let field = EmojiUITextField()
        field.delegate        = context.coordinator
        field.font            = .systemFont(ofSize: 44)
        field.textAlignment   = .center
        field.tintColor       = .clear   // hide blinking cursor
        field.text            = text
        return field
    }

    func updateUIView(_ uiView: EmojiUITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiTextField
        init(_ p: EmojiTextField) { parent = p }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current  = textField.text ?? ""
            let proposed = (current as NSString).replacingCharacters(in: range, with: string)
            // Swift's Character is a grapheme cluster → handles compound emoji correctly
            if let last = proposed.last {
                parent.text  = String(last)
                textField.text = String(last)
            } else {
                parent.text  = ""
                textField.text = ""
            }
            return false
        }
    }
}

// MARK: - EmojiUITextField

/// UITextField subclass that forces the emoji keyboard.
final class EmojiUITextField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
            ?? super.textInputMode
    }
}
