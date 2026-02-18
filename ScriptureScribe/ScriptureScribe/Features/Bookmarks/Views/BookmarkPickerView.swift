//
//  BookmarkPickerView.swift
//  ScriptureScribe
//
//  The sheet that appears when the user taps the bookmark icon on a chapter.
//  They can pick a ribbon color and an emoji to make bookmarks easy to spot in the list.
//

import SwiftUI

struct BookmarkPickerView: View {

    // Passed in from ReaderView
    let chapterReference: String
    let isAlreadyBookmarked: Bool
    let onSave:   (String, String) -> Void  // colorHex, emoji
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedColorHex: String = Bookmark.presetColors[0].hex
    @State private var selectedEmoji:    String = Bookmark.presetEmojis[0]

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {

                // Chapter name at the top so the user knows what they're bookmarking
                Text(chapterReference)
                    .font(.title3.bold())
                    .padding(.top, 8)

                // — Color Picker —
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ribbon Color")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Bookmark.presetColors, id: \.hex) { option in
                                colorSwatch(name: option.name, hex: option.hex)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                // — Emoji Picker —
                VStack(alignment: .leading, spacing: 10) {
                    Text("Emoji")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Bookmark.presetEmojis, id: \.self) { emoji in
                            emojiButton(emoji)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // — Preview —
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: selectedColorHex))
                        .frame(width: 8, height: 52)
                    VStack(alignment: .leading) {
                        Text(selectedEmoji + "  " + chapterReference)
                            .font(.headline)
                        Text("Bookmark preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                Spacer()

                // — Save / Remove —
                if isAlreadyBookmarked {
                    Button(role: .destructive) {
                        onRemove()
                        dismiss()
                    } label: {
                        Label("Remove Bookmark", systemImage: "bookmark.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 20)
                } else {
                    Button {
                        onSave(selectedColorHex, selectedEmoji)
                        dismiss()
                    } label: {
                        Label("Save Bookmark", systemImage: "bookmark.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 20)
                }

                Spacer().frame(height: 8)
            }
            .navigationTitle(isAlreadyBookmarked ? "Edit Bookmark" : "Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Sub-Views

    private func colorSwatch(name: String, hex: String) -> some View {
        let isSelected = selectedColorHex == hex
        return Button {
            selectedColorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(.white, lineWidth: isSelected ? 3 : 0)
                        .padding(3)
                )
                .overlay(
                    Circle()
                        .stroke(Color(hex: hex).opacity(0.5), lineWidth: isSelected ? 2 : 0)
                )
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
        .accessibilityLabel(name)
    }

    private func emojiButton(_ emoji: String) -> some View {
        let isSelected = selectedEmoji == emoji
        return Button {
            selectedEmoji = emoji
        } label: {
            Text(emoji)
                .font(.title2)
                .frame(width: 52, height: 52)
                .background(
                    isSelected ? Color(hex: selectedColorHex).opacity(0.25) : Color(.systemGray6),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color(hex: selectedColorHex) : Color.clear, lineWidth: 2)
                )
        }
        .accessibilityLabel(emoji)
    }
}
