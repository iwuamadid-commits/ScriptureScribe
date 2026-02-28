//
//  VerseImageComposerView.swift
//  ScriptureScribe
//
//  Full-screen image composer for sharing verses as graphics.
//    • Live preview of verse text on a customizable background
//    • Background picker (gradient presets + photo library)
//    • Font picker (built-in iOS fonts displayed in their own typeface)
//    • Toolbar: text size, alignment, contrast, save, share
//

import SwiftUI

struct VerseImageComposerView: View {

    let verseText:      String
    let verseReference: String

    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    @Environment(\.dismiss) private var dismiss

    // Customization state
    @State private var selectedBackground: VerseBackground = .defaultBackground
    @State private var selectedFont:       String          = "Georgia"
    @State private var fontSize:           CGFloat         = 26
    @State private var textAlignment:      TextAlignment   = .center
    @State private var overlayOpacity:     Double          = 0.40

    // Sheet presentation
    @State private var showBackgroundPicker = false
    @State private var showShareSheet       = false
    @State private var showPaywall          = false
    @State private var savedToPhotos        = false

    // Rendered image cache
    @State private var renderedImage: UIImage?

    private var needsWatermark: Bool { !subscriptionVM.isPremium }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── Image preview ─────────────────────────────────────
                    imagePreview
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    Spacer(minLength: 12)

                    // ── Toolbar ───────────────────────────────────────────
                    editorToolbar
                        .padding(.bottom, 4)

                    // ── Font picker ───────────────────────────────────────
                    FontPickerBar(selectedFont: $selectedFont)
                }
            }
            .navigationTitle("Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveToPhotos() }
                        .fontWeight(.semibold)
                        .foregroundStyle(savedToPhotos ? .green : .white)
                }
            }
            .sheet(isPresented: $showBackgroundPicker) {
                BackgroundPickerView(selectedBackground: $selectedBackground)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = renderImage() {
                    ShareSheetView(image: image)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        VStack(spacing: 8) {
            VerseImageCard(
                verseText:      verseText,
                verseReference: verseReference,
                background:     selectedBackground,
                fontName:       selectedFont,
                fontSize:       fontSize,
                textAlignment:  textAlignment,
                overlayOpacity: overlayOpacity,
                showWatermark:  needsWatermark
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .contentShape(Rectangle())
            .onTapGesture { showBackgroundPicker = true }

            if needsWatermark {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                        Text("Remove watermark — Go Premium")
                            .font(.caption)
                    }
                    .foregroundStyle(.yellow.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Editor Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 0) {
            // Text size down
            toolbarButton(icon: "textformat.size.smaller") {
                fontSize = max(16, fontSize - 2)
            }

            // Text size up
            toolbarButton(icon: "textformat.size.larger") {
                fontSize = min(44, fontSize + 2)
            }

            // Text alignment cycle
            toolbarButton(icon: alignmentIcon) {
                switch textAlignment {
                case .center:   textAlignment = .leading
                case .leading:  textAlignment = .trailing
                case .trailing: textAlignment = .center
                }
            }

            // Contrast (overlay opacity)
            toolbarButton(icon: "circle.lefthalf.filled") {
                overlayOpacity = overlayOpacity >= 0.6 ? 0.15 : overlayOpacity + 0.15
            }

            // Choose background
            toolbarButton(icon: "photo.on.rectangle") {
                showBackgroundPicker = true
            }

            // Share
            toolbarButton(icon: "square.and.arrow.up") {
                showShareSheet = true
            }
        }
        .padding(.horizontal, 8)
    }

    private var alignmentIcon: String {
        switch textAlignment {
        case .center:   return "text.aligncenter"
        case .leading:  return "text.alignleft"
        case .trailing: return "text.alignright"
        }
    }

    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Image Rendering

    private func renderImage() -> UIImage? {
        let card = VerseImageCard(
            verseText:      verseText,
            verseReference: verseReference,
            background:     selectedBackground,
            fontName:       selectedFont,
            fontSize:       fontSize * 2,           // 2x for high-res
            textAlignment:  textAlignment,
            overlayOpacity: overlayOpacity,
            showWatermark:  needsWatermark
        )
        .frame(width: 1080, height: 1080)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1   // already sized at 1080x1080
        return renderer.uiImage
    }

    private func saveToPhotos() {
        guard let image = renderImage() else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        withAnimation(.spring(response: 0.3)) { savedToPhotos = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            savedToPhotos = false
        }
    }
}

// MARK: - UIKit Share Sheet Wrapper

/// Wraps UIActivityViewController so we can share a rendered UIImage.
private struct ShareSheetView: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
