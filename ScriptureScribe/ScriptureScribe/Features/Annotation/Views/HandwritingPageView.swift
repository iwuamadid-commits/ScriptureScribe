//
//  HandwritingPageView.swift
//  ScriptureScribe
//
//  Read-only view of a chapter's handwriting, for devices that cannot draw.
//

import PencilKit
import SwiftUI

/// Shows a chapter's handwriting the way it looks on the iPad: over the Bible text.
///
/// iPhone has no Apple Pencil, and handwriting cannot be laid over phone-width
/// text: the strokes were placed against iPad-width lines, so every note would
/// land beside the wrong words once the text reflows. Instead the iPad's page is
/// rebuilt at iPad width, with the translation, layout, font, size, spacing,
/// theme and system text size recorded alongside the drawing, so every line
/// wraps exactly where it did. That page, with the strokes on top, is rendered
/// into one image and made pinch-zoomable, so it reads as the page it was, just
/// smaller. The notebook surface is blank paper, so it shows the strokes alone.
///
/// Read-only by design. Editing here would mean rescaling strokes to phone
/// width and writing them back, which would permanently shrink the iPad's copy.
struct HandwritingPageView: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject var annotationVM: AnnotationViewModel
    /// Handed to BibleTextView when rebuilding the page. The page is drawn with
    /// the iPad's settings, never this phone's, so nothing here is changed.
    @ObservedObject var readerVM: ReaderViewModel
    /// So the page shows the same verse highlights the reader does.
    @ObservedObject var highlightsVM: VerseHighlightsViewModel

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

    /// The rendered page, made once per surface and per sync update rather than on
    /// every redraw (rendering a full chapter page is expensive).
    @State private var pageImage: UIImage?
    @State private var renderedKey: String?
    /// Shown above the page when the Bible text couldn't be loaded.
    @State private var textNote: String?

    private static let api = BibleAPIService()

    /// Changes when there's something new to render: a different surface, or
    /// handwriting that just synced in from the iPad.
    private var renderKey: String { "\(activeId)#\(annotationVM.drawingSyncRevision)" }

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

            if let textNote {
                Text(textNote)
                    .font(.footnote)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if let pageImage {
                ZoomScrollView(minScale: 1.0, maxScale: 6.0, isScrollingDisabled: false) {
                    Image(uiImage: pageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            } else if renderedKey == renderKey {
                emptyState
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Render when the surface changes or new handwriting syncs in, and only then.
        // The previous image stays up while a new one is made, so a sync update
        // swaps in place without a flash.
        .task(id: renderKey) {
            let key = renderKey
            let (image, note) = await renderPage(for: activeId)
            guard !Task.isCancelled else { return }
            pageImage = image
            textNote = note
            renderedKey = key
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

    /// The page for one surface: the rebuilt iPad page with its handwriting, or
    /// the handwriting alone for the notebook (and as a fallback). The second
    /// value explains anything missing.
    private func renderPage(for id: String) async -> (UIImage?, String?) {
        guard let drawing = annotationVM.storedDrawing(for: id),
              !drawing.strokes.isEmpty else { return (nil, nil) }

        // Notebook pages are blank paper: show the writing on its own.
        guard id == chapterId else { return (renderedImage(for: id), nil) }

        // Drawings with no recorded page size can't be placed over text. The iPad
        // sends one for each such page the next time it opens the app.
        guard let geo = annotationVM.drawingGeometry(for: id), geo.width > 1, geo.height > 1 else {
            return (renderedImage(for: id),
                    "The Bible text will show here once your iPad syncs this page.")
        }

        // Pages uploaded before their settings were recorded: this phone's own
        // settings are the best guess until the iPad sends them (it does so once).
        let style = geo.page ?? annotationVM.currentPageStyle()
        guard !style.bibleId.isEmpty,
              let content = try? await Self.api.fetchChapterContent(bibleId: style.bibleId,
                                                                    chapterId: chapterId)
        else {
            return (renderedImage(for: id),
                    "The Bible text couldn't load right now, so only the handwriting is shown.")
        }
        guard !Task.isCancelled else { return (nil, nil) }
        return (rebuiltPage(drawing: drawing, geo: geo, style: style, content: content)
                    ?? renderedImage(for: id), nil)
    }

    /// The iPad's page rebuilt at iPad width, with the strokes on top, as one image.
    private func rebuiltPage(drawing: PKDrawing,
                             geo: AnnotationViewModel.DrawingGeometry,
                             style: AnnotationViewModel.PageStyle,
                             content: BibleChapterContent) -> UIImage? {
        // Tall enough for every stroke: a size estimated for older handwriting,
        // or recorded while the iPad was mid-layout, can fall short of the last one.
        let pageSize = CGSize(width: geo.width,
                              height: max(geo.height, drawing.bounds.maxY + 16))

        // The iPad's theme, in a manager of its own: setting currentTheme directly
        // doesn't save it, so this phone's own theme is left alone.
        let pageTheme = ThemeManager()
        pageTheme.currentTheme = ThemeManager.allThemes.first { $0.name == style.themeName }
            ?? themeManager.currentTheme

        // Same placement as ReaderView: full width puts the text across the whole
        // page; split view puts it in a 60% column, on the right when left-handed.
        let isSplit   = style.layout == AnnotationViewModel.LayoutMode.splitView.rawValue
        let textWidth = isSplit ? floor(pageSize.width * 0.60) : pageSize.width
        let textX     = isSplit && style.leftHanded ? pageSize.width - textWidth : 0

        func page(strokes: UIImage?) -> some View {
            ZStack(alignment: .topLeading) {
                BibleTextView(
                    content:          content,
                    vm:               readerVM,
                    onLongPressVerse: { _, _ in },
                    footerMetrics:    ReaderFooterMetrics(),   // its own, so the reader's isn't touched
                    highlightsVM:     highlightsVM,
                    textStyle:        style.textStyle
                )
                .frame(width: textWidth)
                .offset(x: textX)

                if let strokes {
                    Image(uiImage: strokes)
                        .resizable()
                        .frame(width: pageSize.width, height: pageSize.height)
                } else {
                    Color.clear.frame(width: pageSize.width, height: pageSize.height)
                }
            }
            .frame(width: pageSize.width, alignment: .topLeading)
            .background(pageTheme.currentTheme.background)
            .environmentObject(pageTheme)
            .environment(\.dynamicTypeSize,
                         DynamicTypeSize(UIContentSizeCategory(rawValue: style.contentSize)) ?? .large)
        }

        // The text can run well past the page size (an estimated one only reaches
        // the last stroke), so the sharpness is chosen for the page as laid out.
        let laidOut = UIHostingController(rootView: page(strokes: nil))
            .sizeThatFits(in: CGSize(width: pageSize.width, height: .greatestFiniteMagnitude))
        let scale = renderScale(for: CGSize(width: pageSize.width,
                                            height: max(pageSize.height, laidOut.height)))

        let strokes = strokesImage(drawing, rect: CGRect(origin: .zero, size: pageSize), scale: scale)
        let renderer = ImageRenderer(content: page(strokes: strokes))
        renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: nil)
        renderer.scale = scale
        return renderer.uiImage
    }

    /// Sharp enough to zoom in and read, capped so a long chapter doesn't need
    /// hundreds of megabytes.
    private func renderScale(for size: CGSize) -> CGFloat {
        let maxPixels: CGFloat = 16_000_000
        return min(3, max(1, (maxPixels / max(size.width * size.height, 1)).squareRoot()))
    }

    /// Strokes drawn the way the iPad's canvas shows them (it always uses light
    /// mode), so ink colors don't shift when this phone is in dark mode.
    private func strokesImage(_ drawing: PKDrawing, rect: CGRect, scale: CGFloat) -> UIImage {
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image
    }

    /// Draws the stored strokes into an image at the page they were made on.
    ///
    /// The recorded geometry is what makes this possible — a PKDrawing carries
    /// no page size of its own. Drawings made before that was recorded fall back
    /// to their own stroke bounds, which frames the writing correctly even
    /// though it loses the surrounding margins.
    private func renderedImage(for id: String) -> UIImage? {
        guard let drawing = annotationVM.storedDrawing(for: id),
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

        return strokesImage(drawing, rect: pageRect, scale: scale)
    }
}
