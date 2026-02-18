//
//  BookmarkPickerView.swift
//  ScriptureScribe
//
//  Sheet for bookmarking a chapter. The user picks a ribbon color (preset swatches
//  or a custom color wheel) and an emoji label, then saves or removes the bookmark.
//

import SwiftUI

struct BookmarkPickerView: View {

    let chapterReference:    String
    let isAlreadyBookmarked: Bool
    let onSave:   (String, String) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedColorHex: String  = Bookmark.presetColors[0].hex
    @State private var selectedEmoji:    String  = Bookmark.presetEmojis[0]
    @State private var customUIColor:    UIColor = UIColor(red: 0.96, green: 0.79, blue: 0.26, alpha: 1)
    @State private var useCustomColor   = false
    @State private var showCustomPicker = false

    private var activeColorHex: String {
        useCustomColor ? customUIColor.hexString : selectedColorHex
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Chapter name
                    Text(chapterReference)
                        .font(.title3.bold())
                        .padding(.top, 8)

                    // — Emoji row (shown first so colors are lower) —
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Emoji Label")
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

                    // — Ribbon Color —
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ribbon Color")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        // Preset color swatches
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Bookmark.presetColors, id: \.hex) { option in
                                    colorSwatch(name: option.name, hex: option.hex)
                                }

                                // Custom color button
                                Button {
                                    showCustomPicker = true
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                AngularGradient(
                                                    colors: [.red,.orange,.yellow,.green,.blue,.purple,.red],
                                                    center: .center
                                                )
                                            )
                                            .frame(width: 40, height: 40)
                                        if useCustomColor {
                                            Circle()
                                                .stroke(.white, lineWidth: 3)
                                                .frame(width: 40, height: 40)
                                        }
                                    }
                                }
                                .accessibilityLabel("Custom color")
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // — Live Preview —
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: activeColorHex))
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

                    // — Action Buttons —
                    if isAlreadyBookmarked {
                        Button(role: .destructive) { onRemove(); dismiss() } label: {
                            Label("Remove Bookmark", systemImage: "bookmark.slash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, 20)
                    } else {
                        Button { onSave(activeColorHex, selectedEmoji); dismiss() } label: {
                            Label("Save Bookmark", systemImage: "bookmark.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationTitle(isAlreadyBookmarked ? "Edit Bookmark" : "Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCustomPicker) {
                ColorPickerWheelView(selectedColor: $customUIColor)
                    .presentationDetents([.large])
                    .onDisappear { useCustomColor = true }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sub-Views

    private func colorSwatch(name: String, hex: String) -> some View {
        let isSelected = !useCustomColor && selectedColorHex == hex
        return Button {
            selectedColorHex = hex
            useCustomColor   = false
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(.white, lineWidth: isSelected ? 3 : 0).padding(3))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
        .accessibilityLabel(name)
    }

    private func emojiButton(_ emoji: String) -> some View {
        let isSelected = selectedEmoji == emoji
        return Button { selectedEmoji = emoji } label: {
            Text(emoji)
                .font(.title2)
                .frame(width: 52, height: 52)
                .background(
                    isSelected ? Color(hex: activeColorHex).opacity(0.25) : Color(.systemGray6),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color(hex: activeColorHex) : Color.clear, lineWidth: 2)
                )
        }
        .accessibilityLabel(emoji)
    }
}
