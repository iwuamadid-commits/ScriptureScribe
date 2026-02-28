//
//  CreateGratitudeView.swift
//  ScriptureScribe
//
//  Sheet for sharing a gratitude post (text + optional photo).
//

import PhotosUI
import SwiftUI

struct CreateGratitudeView: View {

    let currentUser: AppUser
    let onPost:      (String, Data?) -> Void   // (text, imageData?)

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var postText:     String          = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data?      = nil
    @State private var previewImage: UIImage?        = nil

    private var canPost: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── Author info ────────────────────────────────
                        HStack(spacing: 10) {
                            UserAvatarView(displayName: currentUser.displayName, photoURL: currentUser.photoURL, size: 38)
                            Text(currentUser.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(themeManager.currentTheme.text)
                        }
                        .padding(.top, 8)

                        // ── Text editor ────────────────────────────────
                        ZStack(alignment: .topLeading) {
                            if postText.isEmpty {
                                Text("What are you grateful for today?")
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $postText)
                                .frame(minHeight: 140)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                        }
                        .foregroundStyle(themeManager.currentTheme.text)
                        .font(.body)

                        // ── Photo picker ───────────────────────────────
                        if let preview = previewImage {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                Button {
                                    selectedItem     = nil
                                    selectedImageData = nil
                                    previewImage     = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                        .padding(8)
                                }
                            }
                        } else {
                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                    Text("Add a photo")
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(themeManager.currentTheme.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Share Gratitude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Share") {
                        onPost(
                            postText.trimmingCharacters(in: .whitespacesAndNewlines),
                            selectedImageData
                        )
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canPost ? themeManager.currentTheme.primary : themeManager.currentTheme.border)
                    .disabled(!canPost)
                }
            }
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    // Convert to JPEG so the upload always gets valid image bytes
                    selectedImageData = uiImage.jpegData(compressionQuality: 0.8) ?? data
                    previewImage = uiImage
                }
            }
        }
    }
}
