//
//  AnnotationCanvasView.swift
//  ScriptureScribe
//
//  A transparent PencilKit drawing surface that overlays the Bible text.
//
//  Background OCR (GoodNotes-style):
//    Whenever the drawing is saved, a Vision text-recognition job is queued
//    on a background thread (debounced 2 s so rapid strokes don't spam OCR).
//    The result is stored in HandwritingIndexService, making every chapter's
//    handwriting instantly searchable from the Search tab.
//
//  Auto-shape (pen tool):
//    Draw a shape, hold still at the end for ~0.5 s, then lift.
//    The stroke snaps to a clean line, circle, or rectangle.
//
//  Straight-line (highlighter tool):
//    Every committed stroke is straightened when the toggle is on.
//

import SwiftUI
import PencilKit
import Vision

// MARK: - PassThroughPKCanvasView

final class PassThroughPKCanvasView: PKCanvasView {

    var allowFingerDrawing:  Bool = true
    var isDrawingToolActive: Bool = false
    var isLassoActive:       Bool = false

    // MARK: Auto-shape hold detection

    var autoShapeEnabled: Bool = false
    var didHoldAtEnd:     Bool = false
    private var lastMoveTime: Date = .distantPast

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastMoveTime = Date()
        didHoldAtEnd = false
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if autoShapeEnabled, let t = touches.first {
            let cur  = t.location(in: self)
            let prev = t.previousLocation(in: self)
            if hypot(cur.x - prev.x, cur.y - prev.y) > 3 { lastMoveTime = Date() }
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if autoShapeEnabled {
            didHoldAtEnd = Date().timeIntervalSince(lastMoveTime) >= 0.5
        }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        didHoldAtEnd = false
        super.touchesCancelled(touches, with: event)
    }

    // MARK: Finger pass-through

    private var _isUserInteractionEnabled: Bool = true
    override var isUserInteractionEnabled: Bool {
        get {
            if !allowFingerDrawing && isDrawingToolActive { return true }
            return _isUserInteractionEnabled
        }
        set { _isUserInteractionEnabled = newValue }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Hand mode: pass ALL touches through the canvas.
        if !isDrawingToolActive && !isLassoActive {
            return nil
        }

        // Drawing tool with finger drawing: accept all touches for drawing
        if allowFingerDrawing && isDrawingToolActive {
            return super.hitTest(point, with: event)
        }

        // Pencil-only drawing or lasso mode:
        // Accept pencil touches for drawing, pass finger touches through
        // so the user can scroll the page with their finger.
        if let touches = event?.allTouches, !touches.isEmpty {
            let allArePencil = touches.allSatisfy { $0.type == .pencil }
            if !allArePencil { return nil }
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - AnnotationCanvasView

struct AnnotationCanvasView: UIViewRepresentable {

    @ObservedObject var vm: AnnotationViewModel
    let chapterId:        String
    let chapterReference: String   // e.g. "Genesis 1" — stored in OCR index
    let contentHeight:    CGFloat
    let containerWidth:   CGFloat

    func makeUIView(context: Context) -> PassThroughPKCanvasView {
        let canvas = PassThroughPKCanvasView()
        canvas.allowFingerDrawing  = vm.allowFingerDrawing
        canvas.isDrawingToolActive = vm.isDrawingTool
        canvas.isLassoActive       = vm.isLassoActive
        canvas.autoShapeEnabled    = vm.highlighterStraightLines && vm.selectedTool == .pen
        canvas.backgroundColor = .clear
        canvas.isOpaque        = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool            = vm.pkTool
        canvas.drawingPolicy   = vm.allowFingerDrawing ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = vm.isDrawingTool || vm.isLassoActive
        canvas.delegate        = context.coordinator
        applyFingerPolicy(to: canvas)

        // On iPhone, disable PKCanvasView's own scrolling and zoom so it doesn't
        // conflict with the parent ZoomScrollView. Without this, finger strokes
        // appear offset and at the wrong scale during drawing, snapping into place
        // only after the touch ends.
        if UIDevice.current.userInterfaceIdiom == .phone {
            canvas.isScrollEnabled  = false
            canvas.minimumZoomScale = 1.0
            canvas.maximumZoomScale = 1.0
            canvas.bouncesZoom      = false
        }

        // Apple Pencil double-tap → toggle eraser
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvas.addInteraction(pencilInteraction)

        context.coordinator.canvas               = canvas
        context.coordinator.currentChapterId     = chapterId
        context.coordinator.currentChapterRef    = chapterReference
        context.coordinator.lastContainerWidth   = containerWidth
        vm.currentChapterId = chapterId

        if let saved = vm.loadDrawing(for: chapterId) {
            context.coordinator.isRewriting = true
            canvas.drawing = saved
            context.coordinator.isRewriting = false
            context.coordinator.previousStrokeCount = saved.strokes.count
        }

        let coordinator = context.coordinator

        // Temporarily enable interaction so the canvas joins the responder chain
        // and exposes its undoManager. Then restore the correct state in updateUIView.
        // Also briefly become first responder so PencilKit registers its undo manager.
        canvas.isUserInteractionEnabled = true
        vm.undoAction = { [weak canvas] in
            // Briefly enable interaction to access the undo manager if in hand mode
            let wasEnabled = canvas?.isUserInteractionEnabled ?? true
            canvas?.isUserInteractionEnabled = true
            canvas?.undoManager?.undo()
            canvas?.isUserInteractionEnabled = wasEnabled
        }
        vm.redoAction = { [weak canvas] in
            let wasEnabled = canvas?.isUserInteractionEnabled ?? true
            canvas?.isUserInteractionEnabled = true
            canvas?.undoManager?.redo()
            canvas?.isUserInteractionEnabled = wasEnabled
        }
        vm.clearCanvasAction = { [weak canvas, weak coordinator] in
            guard let canvas = canvas else { return }
            coordinator?.isRewriting = true
            canvas.drawing = PKDrawing()
            coordinator?.previousStrokeCount = 0
            coordinator?.isRewriting = false
        }
        vm.getDrawingAction  = { [weak canvas] in canvas?.drawing ?? PKDrawing() }
        vm.setDrawingAction  = { [weak canvas, weak coordinator] drawing in
            guard let canvas = canvas else { return }
            coordinator?.isRewriting = true
            canvas.drawing = drawing
            coordinator?.previousStrokeCount = drawing.strokes.count
            coordinator?.isRewriting = false
        }

        return canvas
    }

    func updateUIView(_ canvas: PassThroughPKCanvasView, context: Context) {
        canvas.allowFingerDrawing  = vm.allowFingerDrawing
        canvas.isDrawingToolActive = vm.isDrawingTool
        canvas.isLassoActive       = vm.isLassoActive
        canvas.autoShapeEnabled    = vm.highlighterStraightLines && vm.selectedTool == .pen

        context.coordinator.currentChapterRef = chapterReference

        // Chapter changed → save old drawing, clear canvas, load new
        if context.coordinator.currentChapterId != chapterId {
            let oldId = context.coordinator.currentChapterId
            if !oldId.isEmpty && !canvas.drawing.strokes.isEmpty {
                vm.saveDrawing(canvas.drawing, for: oldId)
            }

            // Reset PencilKit's built-in undo manager so strokes from the
            // previous chapter can never be restored via three-finger swipe,
            // shake, or the undo toolbar button.
            canvas.undoManager?.removeAllActions()

            // Clear the canvas immediately so old strokes never appear on the new chapter
            context.coordinator.isRewriting = true
            canvas.drawing = PKDrawing()
            context.coordinator.isRewriting = false

            context.coordinator.currentChapterId = chapterId
            vm.currentChapterId = chapterId

            let newDrawing = vm.loadDrawing(for: chapterId) ?? PKDrawing()
            context.coordinator.isRewriting = true
            canvas.drawing = newDrawing
            context.coordinator.isRewriting = false
            context.coordinator.previousStrokeCount = newDrawing.strokes.count

            // Clear lasso undo/redo stacks so operations from the old chapter
            // cannot be restored on the new page.
            vm.clearUndoStacks()

            context.coordinator.lastContainerWidth = containerWidth
        }

        // Container width changed (full-width ↔ split-view) → scale strokes
        let previousWidth = context.coordinator.lastContainerWidth
        if previousWidth > 1 && containerWidth > 1 &&
           abs(previousWidth - containerWidth) > 2 {
            let scale     = containerWidth / previousWidth
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let scaled    = canvas.drawing.transformed(using: transform)
            context.coordinator.isRewriting = true
            canvas.drawing = scaled
            context.coordinator.isRewriting = false
            context.coordinator.previousStrokeCount = scaled.strokes.count
            // Only persist if there is actual content — avoids creating empty files
            // that would falsely trigger the annotation indicator dot.
            if !scaled.strokes.isEmpty {
                vm.saveDrawing(scaled, for: chapterId)
            }
        }
        context.coordinator.lastContainerWidth = containerWidth

        canvas.tool            = vm.pkTool
        canvas.drawingPolicy   = vm.allowFingerDrawing ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = vm.isDrawingTool || vm.isLassoActive
        applyFingerPolicy(to: canvas)

        // Keep PKCanvasView's own scrolling disabled on iPhone (reinforced every update)
        if UIDevice.current.userInterfaceIdiom == .phone {
            canvas.isScrollEnabled  = false
            canvas.minimumZoomScale = 1.0
            canvas.maximumZoomScale = 1.0
        }
    }

    // MARK: - Finger policy helper

    private func applyFingerPolicy(to canvas: PKCanvasView) {
        let pencilOnly: [NSNumber] = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        let anyInput:   [NSNumber] = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
        let allowed = vm.allowFingerDrawing ? anyInput : pencilOnly
        for recognizer in canvas.gestureRecognizers ?? [] {
            recognizer.allowedTouchTypes = allowed
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    // MARK: - Coordinator

    class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        let vm: AnnotationViewModel
        var currentChapterId  = ""
        var currentChapterRef = ""
        var lastContainerWidth: CGFloat = 0
        weak var canvas: PKCanvasView?

        var previousStrokeCount = 0
        var isRewriting = false
        private var ocrTimer:    Timer?

        init(vm: AnnotationViewModel) { self.vm = vm }

        // MARK: Apple Pencil double-tap

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            DispatchQueue.main.async { [weak self] in
                self?.vm.handlePencilDoubleTap()
            }
        }

        // MARK: Drawing delegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !currentChapterId.isEmpty else { return }
            guard !isRewriting             else { return }

            // During lasso drag, setDrawingAction fires this delegate every frame.
            // Skip saving/OCR to keep movement smooth — positions are persisted on drag end.
            if vm.suppressCanvasSave {
                previousStrokeCount = canvasView.drawing.strokes.count
                return
            }

            let currentCount = canvasView.drawing.strokes.count
            let strokeAdded  = currentCount > previousStrokeCount
            previousStrokeCount = currentCount

            // Lasso mode: capture the drawn stroke as a lasso path, then remove it.
            // The canvas renders the blue lasso line in real-time via PencilKit;
            // on completion we extract the points and hand them to LassoOverlayView.
            if vm.isLassoActive && strokeAdded {
                if let lastStroke = canvasView.drawing.strokes.last {
                    let pathPoints = (0..<lastStroke.path.count).map {
                        lastStroke.path[$0].location
                    }

                    // Remove the temporary lasso stroke from the canvas
                    var drawing = canvasView.drawing
                    drawing.strokes.removeLast()
                    vm.suppressCanvasSave = true
                    previousStrokeCount = drawing.strokes.count
                    isRewriting = true
                    canvasView.drawing = drawing
                    isRewriting = false
                    vm.suppressCanvasSave = false

                    if pathPoints.count >= 3 {
                        // Defer to next run-loop to avoid nested SwiftUI updates
                        DispatchQueue.main.async { [weak self] in
                            self?.vm.lassoPathPoints = pathPoints
                        }
                    }
                }
                return
            }

            if strokeAdded && vm.selectedTool == .highlighter {
                // Always normalize the highlighter tip to perfectly vertical,
                // then optionally straighten the stroke path.
                if vm.highlighterStraightLines {
                    straightenLastStroke(in: canvasView)
                } else {
                    normalizeHighlighterTip(in: canvasView)
                }
                return
            }

            if strokeAdded && vm.highlighterStraightLines {
                switch vm.selectedTool {
                case .pen:
                    if let pcv = canvasView as? PassThroughPKCanvasView,
                       pcv.didHoldAtEnd,
                       snapToShape(in: canvasView) {
                        return
                    }
                default: break
                }
            }

            save(canvasView.drawing)
        }

        // MARK: - Save + background OCR

        private func save(_ drawing: PKDrawing) {
            vm.saveDrawing(drawing, for: currentChapterId)
            scheduleOCR(drawing: drawing)
        }

        /// Debounced: waits 2 s after the last change before running Vision OCR,
        /// so rapid strokes don't each trigger a full recognition pass.
        private func scheduleOCR(drawing: PKDrawing) {
            ocrTimer?.invalidate()
            let chapterId = currentChapterId
            let reference = currentChapterRef
            ocrTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                DispatchQueue.global(qos: .background).async {
                    Self.runOCR(drawing: drawing, chapterId: chapterId, reference: reference)
                }
            }
        }

        /// Renders the drawing to an image and runs Vision text recognition.
        /// Result is stored in HandwritingIndexService on the main thread.
        private static func runOCR(drawing: PKDrawing, chapterId: String, reference: String) {
            guard !drawing.strokes.isEmpty else {
                DispatchQueue.main.async {
                    HandwritingIndexService.shared.store(text: "", reference: reference, for: chapterId)
                }
                return
            }

            let bounds = drawing.bounds.isEmpty
                ? CGRect(x: 0, y: 0, width: 100, height: 100)
                : drawing.bounds.insetBy(dx: -20, dy: -20)
            let image = drawing.image(from: bounds, scale: 2)
            guard let cgImage = image.cgImage else { return }

            let request = VNRecognizeTextRequest { req, _ in
                let recognized = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                DispatchQueue.main.async {
                    HandwritingIndexService.shared.store(text: recognized,
                                                        reference: reference,
                                                        for: chapterId)
                }
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }

        // MARK: - Straight-line snapping (highlighter)

        /// Fixed azimuth for a perfectly vertical highlighter tip.
        private let verticalTipAzimuth: CGFloat = .pi / 2

        private func straightenLastStroke(in canvasView: PKCanvasView) {
            let strokes = canvasView.drawing.strokes
            guard let last = strokes.last, last.path.count >= 2 else {
                save(canvasView.drawing); return
            }
            let p0 = last.path[0]
            let p1 = last.path[last.path.count - 1]
            let mid = PKStrokePoint(
                location:   CGPoint(x: (p0.location.x + p1.location.x) / 2,
                                    y: (p0.location.y + p1.location.y) / 2),
                timeOffset: (p0.timeOffset + p1.timeOffset) / 2,
                size:       CGSize(width:  (p0.size.width  + p1.size.width)  / 2,
                                   height: (p0.size.height + p1.size.height) / 2),
                opacity:    (p0.opacity  + p1.opacity)  / 2,
                force:      (p0.force    + p1.force)    / 2,
                azimuth:    verticalTipAzimuth,
                altitude:   (p0.altitude + p1.altitude) / 2
            )
            let sp0 = PKStrokePoint(
                location: p0.location, timeOffset: p0.timeOffset,
                size: p0.size, opacity: p0.opacity, force: p0.force,
                azimuth: verticalTipAzimuth, altitude: p0.altitude
            )
            let sp1 = PKStrokePoint(
                location: p1.location, timeOffset: p1.timeOffset,
                size: p1.size, opacity: p1.opacity, force: p1.force,
                azimuth: verticalTipAzimuth, altitude: p1.altitude
            )
            let path     = PKStrokePath(controlPoints: [sp0, mid, sp1],
                                        creationDate: last.path.creationDate)
            let straight = PKStroke(ink: last.ink, path: path, transform: last.transform)
            rewrite(canvasView: canvasView, replacing: strokes.count - 1, with: straight)
        }

        /// Rewrites the last stroke with a fixed vertical azimuth on every point,
        /// keeping the original path shape intact.
        private func normalizeHighlighterTip(in canvasView: PKCanvasView) {
            let strokes = canvasView.drawing.strokes
            guard let last = strokes.last, last.path.count >= 2 else {
                save(canvasView.drawing); return
            }
            let normalized = (0..<last.path.count).map { i -> PKStrokePoint in
                let pt = last.path[i]
                return PKStrokePoint(
                    location:   pt.location,
                    timeOffset: pt.timeOffset,
                    size:       pt.size,
                    opacity:    pt.opacity,
                    force:      pt.force,
                    azimuth:    verticalTipAzimuth,
                    altitude:   pt.altitude
                )
            }
            let path   = PKStrokePath(controlPoints: normalized,
                                       creationDate: last.path.creationDate)
            let stroke = PKStroke(ink: last.ink, path: path, transform: last.transform)
            rewrite(canvasView: canvasView, replacing: strokes.count - 1, with: stroke)
        }

        // MARK: - Auto-shape recognition (pen)

        @discardableResult
        private func snapToShape(in canvasView: PKCanvasView) -> Bool {
            let strokes = canvasView.drawing.strokes
            guard let last = strokes.last, last.path.count >= 3 else { return false }
            let pts = (0..<last.path.count).map { last.path[$0].location }
            guard let shaped = recognizeShape(points: pts, template: last) else { return false }
            rewrite(canvasView: canvasView, replacing: strokes.count - 1, with: shaped)
            return true
        }

        private func recognizeShape(points: [CGPoint], template: PKStroke) -> PKStroke? {
            guard points.count >= 3 else { return nil }
            if straightnessRatio(points) > 0.88 {
                return lineStroke(from: points.first!, to: points.last!, template: template)
            }
            let span = boundingSpan(points)
            guard span > 20 else { return nil }
            let gap = hypot(points.first!.x - points.last!.x,
                            points.first!.y - points.last!.y)
            guard gap / span < 0.30 else { return nil }
            if let (center, radius) = fitCircle(points) {
                return circleStroke(center: center, radius: radius, template: template)
            }
            if let rect = fitRectangle(points) {
                return rectangleStroke(rect: rect, template: template)
            }
            return nil
        }

        // MARK: Shape geometry

        private func straightnessRatio(_ pts: [CGPoint]) -> CGFloat {
            let arc = zip(pts, pts.dropFirst())
                .reduce(CGFloat(0)) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            guard arc > 0 else { return 0 }
            return hypot(pts.last!.x - pts.first!.x, pts.last!.y - pts.first!.y) / arc
        }

        private func boundingSpan(_ pts: [CGPoint]) -> CGFloat {
            let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
            let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
            return hypot(maxX - minX, maxY - minY)
        }

        private func fitCircle(_ pts: [CGPoint]) -> (CGPoint, CGFloat)? {
            let n  = CGFloat(pts.count)
            let cx = pts.map(\.x).reduce(0, +) / n
            let cy = pts.map(\.y).reduce(0, +) / n
            let radii  = pts.map { hypot($0.x - cx, $0.y - cy) }
            let mean   = radii.reduce(0, +) / n
            guard mean > 10 else { return nil }
            let stdDev = sqrt(radii.map { pow($0 - mean, 2) }.reduce(0, +) / n)
            guard stdDev / mean < 0.18 else { return nil }
            return (CGPoint(x: cx, y: cy), mean)
        }

        private func fitRectangle(_ pts: [CGPoint]) -> CGRect? {
            let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
            let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
            let w = maxX - minX, h = maxY - minY
            guard w > 20, h > 20 else { return nil }
            let thr  = min(w, h) * 0.22
            let near = pts.filter {
                abs($0.x - minX) < thr || abs($0.x - maxX) < thr ||
                abs($0.y - minY) < thr || abs($0.y - maxY) < thr
            }
            guard CGFloat(near.count) / CGFloat(pts.count) > 0.72 else { return nil }
            return CGRect(x: minX, y: minY, width: w, height: h)
        }

        // MARK: Shape stroke builders

        private func lineStroke(from start: CGPoint, to end: CGPoint,
                                template: PKStroke) -> PKStroke {
            let n  = template.path.count
            let t0 = template.path[0], t1 = template.path[n - 1]
            let mid = PKStrokePoint(
                location:   CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2),
                timeOffset: (t0.timeOffset + t1.timeOffset) / 2,
                size:       CGSize(width:  (t0.size.width  + t1.size.width)  / 2,
                                   height: (t0.size.height + t1.size.height) / 2),
                opacity:    (t0.opacity  + t1.opacity)  / 2,
                force:      (t0.force    + t1.force)    / 2,
                azimuth:    (t0.azimuth  + t1.azimuth)  / 2,
                altitude:   (t0.altitude + t1.altitude) / 2
            )
            let path = PKStrokePath(controlPoints: [t0, mid, t1],
                                    creationDate: template.path.creationDate)
            return PKStroke(ink: template.ink, path: path, transform: template.transform)
        }

        private func circleStroke(center: CGPoint, radius: CGFloat,
                                  template: PKStroke) -> PKStroke {
            let t0 = template.path[0]
            let avgSize  = averageSize(template.path)
            let avgProps = averageProps(template.path)
            var cpts: [PKStrokePoint] = []
            for i in 0...32 {
                let angle = CGFloat(i) / 32 * 2 * .pi
                cpts.append(PKStrokePoint(
                    location:   CGPoint(x: center.x + radius * cos(angle),
                                        y: center.y + radius * sin(angle)),
                    timeOffset: t0.timeOffset + Double(i) * 0.01,
                    size: avgSize, opacity: avgProps.opacity, force: avgProps.force,
                    azimuth: t0.azimuth, altitude: t0.altitude
                ))
            }
            let path = PKStrokePath(controlPoints: cpts, creationDate: template.path.creationDate)
            return PKStroke(ink: template.ink, path: path, transform: template.transform)
        }

        private func rectangleStroke(rect: CGRect, template: PKStroke) -> PKStroke {
            let t0       = template.path[0]
            let avgSize  = averageSize(template.path)
            let avgProps = averageProps(template.path)
            let corners: [CGPoint] = [
                CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.minY)
            ]
            var locs: [CGPoint] = []
            for i in 0..<4 {
                locs.append(corners[i])
                locs.append(CGPoint(x: (corners[i].x + corners[i+1].x) / 2,
                                    y: (corners[i].y + corners[i+1].y) / 2))
            }
            locs.append(corners[0])
            let cpts = locs.enumerated().map { i, loc in
                PKStrokePoint(location: loc, timeOffset: t0.timeOffset + Double(i) * 0.01,
                              size: avgSize, opacity: avgProps.opacity, force: avgProps.force,
                              azimuth: t0.azimuth, altitude: t0.altitude)
            }
            let path = PKStrokePath(controlPoints: cpts, creationDate: template.path.creationDate)
            return PKStroke(ink: template.ink, path: path, transform: template.transform)
        }

        // MARK: Stroke attribute helpers

        private func averageSize(_ path: PKStrokePath) -> CGSize {
            let n = CGFloat(path.count)
            let w = (0..<path.count).map { path[$0].size.width  }.reduce(0, +) / n
            let h = (0..<path.count).map { path[$0].size.height }.reduce(0, +) / n
            return CGSize(width: w, height: h)
        }

        private struct StrokeProps { let opacity: CGFloat; let force: CGFloat }
        private func averageProps(_ path: PKStrokePath) -> StrokeProps {
            let n = CGFloat(path.count)
            let o = (0..<path.count).map { path[$0].opacity }.reduce(0, +) / n
            let f = (0..<path.count).map { path[$0].force   }.reduce(0, +) / n
            return StrokeProps(opacity: o, force: f)
        }

        // MARK: Write-back helper

        private func rewrite(canvasView: PKCanvasView, replacing index: Int,
                             with stroke: PKStroke) {
            var strokes = canvasView.drawing.strokes
            guard index < strokes.count else { return }
            strokes[index] = stroke
            // Undo PencilKit's original stroke registration first, then set the
            // modified drawing.  This collapses the two actions (add + rewrite)
            // into a single undoable step so one undo removes the whole stroke.
            isRewriting = true
            canvasView.undoManager?.undo()
            canvasView.drawing = PKDrawing(strokes: strokes)
            isRewriting = false
            previousStrokeCount = canvasView.drawing.strokes.count
            save(canvasView.drawing)
        }
    }
}
