//
//  CropView.swift
//  ScriptureScribe
//
//  Full-screen crop editor shown when the user taps "Crop" on a placed photo.
//
//  Layout (mirrors the GoodNotes-style UI from the design mockup):
//    Cancel   Reset   |   Rectangle | Freehand   |   ⇆  ↕   Done
//
//  • Rectangle mode — drag the four corner handles to define the crop area.
//    A rule-of-thirds grid and darkened surround give live visual feedback.
//  • Freehand mode — draw any closed shape with one finger; the image is
//    clipped to that path (transparent outside) when Done is tapped.
//  • Flip H / Flip V — mirror the image horizontally or vertically; the
//    live preview updates instantly.
//  • Reset — restores the full image, clears any drawn path, undoes flips.
//  • Cancel — dismisses with no changes.
//  • Done — applies all edits and returns the resulting UIImage via onComplete.
//

import SwiftUI

struct CropView: View {

    let originalImage: UIImage
    var onComplete: (UIImage) -> Void
    var onCancel:   () -> Void

    // MARK: - Types

    enum CropMode: String, CaseIterable {
        case rectangle = "Rectangle"
        case freehand  = "Freehand"
    }

    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private struct CornerDrag {
        var corner:      Corner
        var translation: CGSize
    }

    // MARK: - State

    @State private var cropMode:       CropMode = .rectangle
    /// Normalized crop rect — each value is 0…1 fraction of the image dimensions.
    @State private var cropNorm:       CGRect   = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Live delta while a corner handle is being dragged (resets automatically on lift).
    @GestureState private var cornerDrag: CornerDrag? = nil
    /// Points collected during a freehand draw, in the container's coordinate space.
    @State private var freehandPoints: [CGPoint] = []
    @State private var isFlippedH:     Bool     = false
    @State private var isFlippedV:     Bool     = false
    /// Stored so apply() can convert freehand display-points → image pixels.
    @State private var imgRect:        CGRect   = .zero

    private let minCropFrac: CGFloat = 0.05

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                GeometryReader { geo in
                    let computed = imageDisplayRect(in: geo.size)
                    let live     = liveCropNorm
                    let cr = CGRect(
                        x:      computed.minX + live.minX * computed.width,
                        y:      computed.minY + live.minY * computed.height,
                        width:  live.width  * computed.width,
                        height: live.height * computed.height
                    )

                    ZStack {
                        // Image — with live flip preview
                        Image(uiImage: originalImage)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(x: isFlippedH ? -1 : 1,
                                         y: isFlippedV ? -1 : 1)
                            .frame(width: geo.size.width, height: geo.size.height)

                        switch cropMode {
                        case .rectangle:
                            rectangleOverlay(container: geo.size, imgRect: computed, cr: cr)
                        case .freehand:
                            freehandOverlay(container: geo.size)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .onAppear            { imgRect = computed }
                    .onChange(of: geo.size) { _, s in imgRect = imageDisplayRect(in: s) }
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            Button("Cancel") { onCancel() }
                .foregroundStyle(.white)

            Button("Reset") { reset() }
                .foregroundStyle(.white)

            Spacer()

            Picker("Mode", selection: $cropMode) {
                ForEach(CropMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .onChange(of: cropMode) { _, _ in freehandPoints = [] }

            Spacer()

            // Flip horizontal
            Button { isFlippedH.toggle() } label: {
                Image(systemName: "flip.horizontal")
                    .font(.title3)
            }
            .foregroundStyle(isFlippedH ? Color.accentColor : .white)

            // Flip vertical (same icon, rotated 90°)
            Button { isFlippedV.toggle() } label: {
                Image(systemName: "flip.horizontal")
                    .font(.title3)
                    .rotationEffect(.degrees(90))
            }
            .foregroundStyle(isFlippedV ? Color.accentColor : .white)

            Button("Done") { apply() }
                .fontWeight(.semibold)
                .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(white: 0.12))
    }

    // MARK: - Rectangle overlay

    @ViewBuilder
    private func rectangleOverlay(container: CGSize, imgRect: CGRect, cr: CGRect) -> some View {
        // Dark surround + rule-of-thirds grid + crop border
        Canvas { ctx, size in
            // Even-odd fill: outer rect filled, crop rect punched out
            var mask = Path(CGRect(origin: .zero, size: size))
            mask.addRect(cr)
            ctx.fill(mask, with: .color(.black.opacity(0.55)),
                     style: FillStyle(eoFill: true))

            // Rule-of-thirds grid
            let grid = GraphicsContext.Shading.color(.white.opacity(0.30))
            for i in 1...2 {
                let xLine = cr.minX + cr.width  * CGFloat(i) / 3
                let yLine = cr.minY + cr.height * CGFloat(i) / 3
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: xLine, y: cr.minY))
                    p.addLine(to: CGPoint(x: xLine, y: cr.maxY))
                }, with: grid, lineWidth: 0.5)
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: cr.minX, y: yLine))
                    p.addLine(to: CGPoint(x: cr.maxX, y: yLine))
                }, with: grid, lineWidth: 0.5)
            }

            // White border
            ctx.stroke(Path(cr), with: .color(.white), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
        .frame(width: container.width, height: container.height)

        // Four draggable corner handles
        cornerHandle(.topLeft,     cr: cr, imgRect: imgRect)
        cornerHandle(.topRight,    cr: cr, imgRect: imgRect)
        cornerHandle(.bottomLeft,  cr: cr, imgRect: imgRect)
        cornerHandle(.bottomRight, cr: cr, imgRect: imgRect)
    }

    // MARK: - Freehand overlay

    @ViewBuilder
    private func freehandOverlay(container: CGSize) -> some View {
        Canvas { ctx, size in
            guard freehandPoints.count >= 2 else { return }

            var path = Path()
            path.move(to: freehandPoints[0])
            freehandPoints.dropFirst().forEach { path.addLine(to: $0) }

            // Once the user has a meaningful shape, dim the area outside
            if freehandPoints.count > 6 {
                var closed = path
                closed.closeSubpath()
                var mask = Path(CGRect(origin: .zero, size: size))
                mask.addPath(closed)
                ctx.fill(mask, with: .color(.black.opacity(0.50)),
                         style: FillStyle(eoFill: true))
            }

            ctx.stroke(path, with: .color(.white),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
        .frame(width: container.width, height: container.height)

        // Transparent gesture capture layer sits above the Canvas
        Color.clear
            .contentShape(Rectangle())
            .frame(width: container.width, height: container.height)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if freehandPoints.isEmpty {
                            freehandPoints.append(value.startLocation)
                        }
                        freehandPoints.append(value.location)
                    }
                    .onEnded { _ in
                        // Close the path
                        if let first = freehandPoints.first {
                            freehandPoints.append(first)
                        }
                    }
            )
    }

    // MARK: - Corner handle

    @ViewBuilder
    private func cornerHandle(_ corner: Corner, cr: CGRect, imgRect: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: 24, height: 24)
            .shadow(color: .black.opacity(0.35), radius: 3)
            .position(cornerPosition(corner, in: cr))
            .gesture(
                DragGesture()
                    .updating($cornerDrag) { value, state, _ in
                        state = CornerDrag(corner: corner, translation: value.translation)
                    }
                    .onEnded { value in
                        cropNorm = updatedCrop(from: cropNorm,
                                               corner: corner,
                                               translation: value.translation,
                                               imgRect: imgRect)
                    }
            )
    }

    private func cornerPosition(_ corner: Corner, in cr: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:     return CGPoint(x: cr.minX, y: cr.minY)
        case .topRight:    return CGPoint(x: cr.maxX, y: cr.minY)
        case .bottomLeft:  return CGPoint(x: cr.minX, y: cr.maxY)
        case .bottomRight: return CGPoint(x: cr.maxX, y: cr.maxY)
        }
    }

    // MARK: - Live crop rect (corner drag preview)

    private var liveCropNorm: CGRect {
        guard let drag = cornerDrag, imgRect.width > 0 else { return cropNorm }
        return updatedCrop(from: cropNorm,
                           corner: drag.corner,
                           translation: drag.translation,
                           imgRect: imgRect)
    }

    /// Pure function: given a start rect and a drag delta, return the new normalized crop rect.
    private func updatedCrop(from start: CGRect,
                             corner: Corner,
                             translation: CGSize,
                             imgRect: CGRect) -> CGRect {
        guard imgRect.width > 0, imgRect.height > 0 else { return start }
        let dx = translation.width  / imgRect.width
        let dy = translation.height / imgRect.height
        var r  = start

        switch corner {
        case .topLeft:
            let newMinX = max(0, start.minX + dx)
            let newMinY = max(0, start.minY + dy)
            if start.maxX - newMinX >= minCropFrac {
                r.origin.x   = newMinX
                r.size.width = start.maxX - newMinX
            }
            if start.maxY - newMinY >= minCropFrac {
                r.origin.y    = newMinY
                r.size.height = start.maxY - newMinY
            }

        case .topRight:
            let newMaxX = min(1, start.maxX + dx)
            let newMinY = max(0, start.minY + dy)
            if newMaxX - start.minX >= minCropFrac { r.size.width = newMaxX - start.minX }
            if start.maxY - newMinY >= minCropFrac {
                r.origin.y    = newMinY
                r.size.height = start.maxY - newMinY
            }

        case .bottomLeft:
            let newMinX = max(0, start.minX + dx)
            let newMaxY = min(1, start.maxY + dy)
            if start.maxX - newMinX >= minCropFrac {
                r.origin.x   = newMinX
                r.size.width = start.maxX - newMinX
            }
            if newMaxY - start.minY >= minCropFrac { r.size.height = newMaxY - start.minY }

        case .bottomRight:
            let newMaxX = min(1, start.maxX + dx)
            let newMaxY = min(1, start.maxY + dy)
            if newMaxX - start.minX >= minCropFrac { r.size.width  = newMaxX - start.minX }
            if newMaxY - start.minY >= minCropFrac { r.size.height = newMaxY - start.minY }
        }

        return r
    }

    // MARK: - Coordinate helpers

    /// The rect (in the container's coordinate space) occupied by the displayed image.
    private func imageDisplayRect(in containerSize: CGSize) -> CGRect {
        let iw = originalImage.size.width
        let ih = originalImage.size.height
        guard iw > 0, ih > 0 else { return CGRect(origin: .zero, size: containerSize) }
        let scale = min(containerSize.width / iw, containerSize.height / ih)
        let dw = iw * scale
        let dh = ih * scale
        return CGRect(
            x: (containerSize.width  - dw) / 2,
            y: (containerSize.height - dh) / 2,
            width: dw, height: dh
        )
    }

    // MARK: - Actions

    private func reset() {
        cropNorm       = CGRect(x: 0, y: 0, width: 1, height: 1)
        freehandPoints = []
        isFlippedH     = false
        isFlippedV     = false
    }

    private func apply() {
        // Step 1: normalize orientation and apply flips
        var result = normalizedImage(originalImage)
        if isFlippedH || isFlippedV {
            result = flipped(result, h: isFlippedH, v: isFlippedV)
        }

        // Step 2: apply crop
        switch cropMode {
        case .rectangle:
            let iw = result.size.width
            let ih = result.size.height
            let cr = CGRect(x: cropNorm.minX * iw, y: cropNorm.minY * ih,
                            width: cropNorm.width * iw, height: cropNorm.height * ih)
            // Only crop if meaningfully different from the full image
            if cr.width < iw - 1 || cr.height < ih - 1 {
                result = rectangleCrop(result, to: cr)
            }

        case .freehand:
            if freehandPoints.count >= 3, imgRect.width > 0 {
                result = freehandCrop(result, points: freehandPoints, imgRect: imgRect)
            }
        }

        onComplete(result)
    }

    // MARK: - Image processing

    /// Re-draws the image into a fresh context so that imageOrientation is always .up.
    /// This ensures CGImage.cropping(to:) operates on the correct pixel layout.
    private func normalizedImage(_ image: UIImage) -> UIImage {
        let fmt      = UIGraphicsImageRendererFormat()
        fmt.scale    = image.scale
        fmt.opaque   = false
        return UIGraphicsImageRenderer(size: image.size, format: fmt).image { _ in
            image.draw(at: .zero)
        }
    }

    private func flipped(_ image: UIImage, h: Bool, v: Bool) -> UIImage {
        let fmt    = UIGraphicsImageRendererFormat()
        fmt.scale  = image.scale
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: fmt).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: h ? image.size.width : 0,
                          y: v ? image.size.height : 0)
            c.scaleBy(x: h ? -1 : 1, y: v ? -1 : 1)
            image.draw(at: .zero)
        }
    }

    private func rectangleCrop(_ image: UIImage, to rect: CGRect) -> UIImage {
        let s = image.scale
        let scaledRect = CGRect(x: rect.minX * s, y: rect.minY * s,
                                width: rect.width * s, height: rect.height * s)
        guard let cgImg = image.cgImage?.cropping(to: scaledRect) else { return image }
        return UIImage(cgImage: cgImg, scale: s, orientation: .up)
    }

    private func freehandCrop(_ image: UIImage,
                               points: [CGPoint],
                               imgRect: CGRect) -> UIImage {
        guard imgRect.width > 0, imgRect.height > 0 else { return image }
        let iw = image.size.width
        let ih = image.size.height

        // Map display-space points → image pixel coordinates
        let imgPoints = points.map { pt in
            CGPoint(x: ((pt.x - imgRect.minX) / imgRect.width)  * iw,
                    y: ((pt.y - imgRect.minY) / imgRect.height) * ih)
        }

        // Build the clip path
        let bezier = UIBezierPath()
        bezier.move(to: imgPoints[0])
        imgPoints.dropFirst().forEach { bezier.addLine(to: $0) }
        bezier.close()

        // Tight bounding box, clamped to image bounds
        let pathBounds = bezier.bounds.intersection(
            CGRect(origin: .zero, size: CGSize(width: iw, height: ih))
        )
        guard pathBounds.width > 1, pathBounds.height > 1 else { return image }

        // Render with transparency (PNG-compatible)
        let fmt      = UIGraphicsImageRendererFormat()
        fmt.scale    = image.scale
        fmt.opaque   = false
        return UIGraphicsImageRenderer(size: pathBounds.size, format: fmt).image { ctx in
            ctx.cgContext.translateBy(x: -pathBounds.minX, y: -pathBounds.minY)
            bezier.addClip()
            image.draw(at: .zero)
        }
    }
}
