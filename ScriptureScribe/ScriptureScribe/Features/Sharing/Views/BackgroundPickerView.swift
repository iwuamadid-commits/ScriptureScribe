//
//  BackgroundPickerView.swift
//  ScriptureScribe
//
//  Sheet for choosing a verse image background.
//    • "Suggested" section — gradient presets displayed as thumbnail cards
//    • "Choose Your Own" section — pick a photo from the library
//

import SwiftUI
import PhotosUI

struct BackgroundPickerView: View {

    @Binding var selectedBackground: VerseBackground
    @Environment(\.dismiss) private var dismiss

    // PhotosPicker selection
    @State private var photoItem: PhotosPickerItem?
    @State private var loadingPhoto = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // ── Suggested Gradients ──────────────────────────────────
                    Text("SUGGESTED")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(GradientPreset.presets) { preset in
                            gradientThumbnail(preset)
                        }
                    }
                    .padding(.horizontal, 20)

                    // ── Create Your Own ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CREATE YOUR OWN")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Choose Your Background Image")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)

                    // Photo library picker
                    PhotosPicker(
                        selection: $photoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Choose from Photo Library")
                                    .font(.subheadline.weight(.medium))
                                if loadingPhoto {
                                    Text("Loading...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)

                    // Show current photo if one is selected
                    if case .photo(let img) = selectedBackground {
                        currentPhotoPreview(img)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Choose Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let item = newItem else { return }
                loadingPhoto = true
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedBackground = .photo(image)
                        dismiss()
                    }
                    loadingPhoto = false
                }
            }
        }
    }

    // MARK: - Gradient Thumbnail

    private func gradientThumbnail(_ preset: GradientPreset) -> some View {
        let isSelected: Bool = {
            if case .gradient(let sel) = selectedBackground { return sel.id == preset.id }
            return false
        }()

        return Button {
            selectedBackground = .gradient(preset)
            dismiss()
        } label: {
            LinearGradient(
                colors:     preset.colors,
                startPoint: preset.startPoint,
                endPoint:   preset.endPoint
            )
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(isSelected ? 0.3 : 0.1), radius: 4, y: 2)
        }
    }

    // MARK: - Current Photo Preview

    private func currentPhotoPreview(_ image: UIImage) -> some View {
        VStack(spacing: 8) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Current background")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
