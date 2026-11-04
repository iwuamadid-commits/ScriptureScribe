//
//  HandwritingPageView.swift
//  ScriptureScribe
//
//  Read-only view of a chapter's handwriting, for devices that cannot draw.
//

import PencilKit
import SwiftUI

/// Shows a chapter's handwriting on its own page, without the Bible text.
///
/// iPhone has no Apple Pencil, and handwriting cannot be laid over phone-width
/// text anyway: the strokes were placed against iPad-width lines, so every word
/// would sit somewhere else once the text reflows. Instead the strokes are
/// rendered at the proportions they were drawn at and made pinch-zoomable, so
/// the page reads as the page it was — just smaller.
///
/// Read-only by design. Editing here would mean rescaling strokes to phone
/// width and writing them back, which would permanently shrink the iPad's copy.
struct HandwritingPageView: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject var annotationVM: AnnotationViewModel

    let chapterId:        String
    let chapterReference: String

    @Environment(\.dismiss) private var dismiss

    /// The two places handwriting can live for one chapter: over the Bible text,
    /// and on the separate blank notebook page.
    private enum Surface: String, CaseIterable {
        case page     = "On the page"
        case notebook = "Notebook"
    }

    @State private var surface: Surface = .page

    private var notebookChapterId: String { "notebook_\(chapterId)" }

    private var hasPage:     Bool { annotationVM.chaptersWithStrokes.contains(chapterId) }
    private var hasNotebook: Bool { annotationVM.chaptersWithStrokes.contains(notebookChapterId) }

    private var activeId: String {
        surface == .notebook ? notebookChapterId : chapterId
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasPage || hasNotebook {
                    content
                } else {
                    emptyState
                }
            }
            .background(themeManager.currentTheme.background)
            .navigationTitle(chapterReference)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
        }
        .onAppear {
            // Open on whichever surface actually has something on it.
            if !hasPage, hasNotebook { surface = .notebook }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            // Only worth choosing between them when both exist.
            if hasPage, hasNotebook {
                Picker("Surface", selection: $surface) {
                    ForEach(Surface.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if let image = renderedImage(for: activeId) {
                ZoomScrollView(minScale: 1.0, maxScale: 6.0, isScrollingDisabled: false) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.draw")
                .font(.system(size: 44))
                .foregroundStyle(themeManager.currentTheme.textSecondary)
            Text("No handwriting on this chapter")
                .font(.headline)
                .foregroundStyle(themeManager.currentTheme.text)
            Text("Notes written on your iPad appear here.")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rendering

    /// Draws the stored strokes into an image at the page they were made on.
    ///
    /// The recorded geometry is what makes this possible — a PKDrawing carries
    /// no page size of its own. Drawings made before that was recorded fall back
    /// to their own stroke bounds, which frames the writing correctly even
    /// though it loses the surrounding margins.
    private func renderedImage(for id: String) -> UIImage? {
        guard let drawing = annotationVM.loadDrawing(for: id),
              !drawing.strokes.isEmpty else { return nil }

        let pageRect: CGRect
        if let geo = annotationVM.drawingGeometry(for: id), geo.width > 1, geo.height > 1 {
            pageRect = CGRect(x: 0, y: 0, width: geo.width, height: geo.height)
        } else {
            pageRect = drawing.bounds.insetBy(dx: -16, dy: -16)
        }
        guard pageRect.width > 1, pageRect.height > 1 else { return nil }

        // A full chapter page can be several thousand points tall, and rendering
        // that at 2x would allocate tens of megabytes. Cap the total pixels and
        // let the scale fall where it must — zooming is handled by the scroll
        // view, not by rendering at a huge size up front.
        let maxPixels: CGFloat = 4_000_000
        let pixelsAt1x = pageRect.width * pageRect.height
        let scale = min(2, max(1, (maxPixels / max(pixelsAt1x, 1)).squareRoot()))

        return drawing.image(from: pageRect, scale: scale)
    }
}
