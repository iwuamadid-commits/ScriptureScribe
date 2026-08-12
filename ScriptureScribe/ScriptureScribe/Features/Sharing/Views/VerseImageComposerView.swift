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

    // ImageRenderer starts from a fresh environment rather than inheriting this
    // view's, so the current Dynamic Type size is captured here and re-injected
    // into the rendered card. Without it the preview honours the device's text
    // size setting while the saved image always renders at the default.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    /// Actual on-screen side length (points) of the preview card. The export is
    /// laid out at this exact size so every fixed constant inside VerseImageCard
    /// (padding, watermark, spacing, shadows) keeps identical proportions;
    /// resolution comes purely from the raster scale.
    @State private var previewSide: CGFloat = 0

    /// Ensures the starting font size is scaled to the card only once, on first layout.
    @State private var didInitFontSize = false

    private var needsWatermark: Bool { !subscriptionVM.isPremium }

    // MARK: - Text size range
    //
    // The 16–44 pt range was tuned against an iPhone-sized card. An iPad's preview
    // is roughly twice as wide, so those literals top out far too small there —
    // and now that the saved image matches the preview, that ceiling would show up
    // in the saved picture too. Scale the range by the measured card size, clamped
    // at 1 so iPhone behaviour is unchanged.

    private let referenceSide: CGFloat = 360

    private var sizeScale: CGFloat {
        previewSide > 0 ? max(1, previewSide / referenceSide) : 1
    }
    private var minFontSize: CGFloat { 16 * sizeScale }
    private var maxFontSize: CGFloat { 44 * sizeScale }
    private var fontStep:    CGFloat {  2 * sizeScale }

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
            // Record the card's resolved size so renderImage() can lay the export
            // out identically. Placed before .clipShape so it measures the card
            // itself, not the styled preview chrome. Purely observational —
            // it has no effect on layout.
            .onGeometryChange(for: CGFloat.self) { proxy in
                min(proxy.size.width, proxy.size.height)
            } action: { newSide in
                previewSide = newSide
                if !didInitFontSize, newSide > 0 {
                    didInitFontSize = true
                    fontSize = 26 * sizeScale
                }
            }
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
                        Text("Remove Watermark (Upgrade to Pro)")
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
            toolbarButton(icon: "textformat.size.smaller", label: "Decrease text size") {
                fontSize = max(minFontSize, fontSize - fontStep)
            }

            // Text size up
            toolbarButton(icon: "textformat.size.larger", label: "Increase text size") {
                fontSize = min(maxFontSize, fontSize + fontStep)
            }

            // Text alignment cycle
            toolbarButton(icon: alignmentIcon, label: "Change text alignment") {
                switch textAlignment {
                case .center:   textAlignment = .leading
                case .leading:  textAlignment = .trailing
                case .trailing: textAlignment = .center
                }
            }

            // Contrast (overlay opacity)
            toolbarButton(icon: "circle.lefthalf.filled", label: "Adjust contrast") {
                overlayOpacity = overlayOpacity >= 0.6 ? 0.15 : overlayOpacity + 0.15
            }

            // Choose background
            toolbarButton(icon: "photo.on.rectangle", label: "Choose background") {
                showBackgroundPicker = true
            }

            // Share
            toolbarButton(icon: "square.and.arrow.up", label: "Share image") {
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

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    // MARK: - Image Rendering

    private func renderImage() -> UIImage? {
        // Lay the card out at exactly the preview's point size rather than at
        // 1080. VerseImageCard's padding, watermark, stack spacing and shadows
        // are fixed point values, so sizing the card differently from the preview
        // silently changes every proportion — the text column widens and the
        // verse rewraps, which is what made saved images look different. Matching
        // the point geometry keeps all of it identical; the 1080x1080 output comes
        // from the raster scale instead.
        let side = previewSide > 0 ? previewSide : referenceSide

        let card = VerseImageCard(
            verseText:      verseText,
            verseReference: verseReference,
            background:     selectedBackground,
            fontName:       selectedFont,
            fontSize:       fontSize,
            textAlignment:  textAlignment,
            overlayOpacity: overlayOpacity,
            showWatermark:  needsWatermark
        )
        .frame(width: side, height: side)
        .environment(\.dynamicTypeSize, dynamicTypeSize)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1080 / side
        guard let image = renderer.uiImage else { return nil }

        // A fractional scale can round the backing bitmap to 1081 px. Rare, but
        // redraw once at exact dimensions when it happens so output is always 1080².
        guard let cg = image.cgImage, cg.width == 1080, cg.height == 1080 else {
            let format = UIGraphicsImageRendererFormat()
            format.scale  = 1
            format.opaque = true
            return UIGraphicsImageRenderer(
                size: CGSize(width: 1080, height: 1080), format: format
            ).image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: 1080, height: 1080))
            }
        }
        return image
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
