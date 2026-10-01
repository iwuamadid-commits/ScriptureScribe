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
//  Auto Shapes (pen tool, when turned on):
//    Draw a shape and keep the pencil still at the end for ~0.5 s. While the pencil
//    is still down, the stroke is replaced by a clean line, circle, oval, triangle,
//    square, rectangle, other straight-sided shape, or straight zig-zag
//    (see ShapeRecognizer). Strokes that aren't a shape stay hand-drawn.
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

    // MARK: Auto Shapes

    /// Pen tool with Auto Shapes on. The hold is detected by the Coordinator, which
    /// watches PencilKit's drawing gesture.
    var autoShapeEnabled: Bool = false

    // MARK: Disable PencilKit edit menu (Select All / Insert Space)

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
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

        // Auto Shapes: watch the pencil while it's down to spot a hold at the end of a
        // stroke. Adding a target only observes the gesture; drawing is unaffected.
        canvas.drawingGestureRecognizer.addTarget(context.coordinator,
                                                  action: #selector(Coordinator.handleDrawingGesture(_:)))

        // Disable PKCanvasView's own scrolling and zoom so it doesn't
        // conflict with the parent ZoomScrollView. Without this, the canvas
        // maintains its own scroll offset and zoom level, which causes:
        //   - Finger strokes appearing offset and at the wrong scale (iPhone)
        //   - Loaded drawings from previous sessions becoming un-erasable because
        //     the eraser operates in the canvas's content coordinate space, which
        //     diverges from the visual position when the canvas has its own scroll state
        canvas.isScrollEnabled  = false
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 1.0
        canvas.bouncesZoom      = false

        // Apple Pencil double-tap → toggle eraser
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvas.addInteraction(pencilInteraction)

        // Swallow finger taps so PencilKit's edit menu ("Select All / Insert Space")
        // never appears. Only responds to direct (finger) touches — pencil is unaffected.
        let tapEater = UITapGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.eatTap))
        tapEater.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        canvas.addGestureRecognizer(tapEater)

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

            // Force PKCanvasView to rebuild its internal stroke hit-test index.
            // Without this, the eraser tool cannot find strokes that were loaded
            // programmatically (i.e. from a previous session's saved drawing).
            // Clear the undo manager after re-setting so that the "set drawing"
            // action isn't on the undo stack — otherwise pressing undo would
            // remove ALL loaded strokes in one step instead of one at a time.
            let coord = context.coordinator
            DispatchQueue.main.async { [weak canvas] in
                guard let canvas = canvas else { return }
                coord.isRewriting = true
                // Assigning the identical drawing back can be optimised away, leaving
                // the hit-test index stale and the strokes un-erasable. Go via an empty
                // drawing and rebuild from the strokes so the value genuinely changes.
                let strokes = canvas.drawing.strokes
                canvas.drawing = PKDrawing()
                canvas.drawing = PKDrawing(strokes: strokes)
                coord.isRewriting = false
                canvas.undoManager?.removeAllActions()
            }
        }

        let coordinator = context.coordinator

        // Temporarily enable interaction so the canvas joins the responder chain
        // and exposes its undoManager. Then restore the correct state in updateUIView.
        // Also briefly become first responder so PencilKit registers its undo manager.
        canvas.isUserInteractionEnabled = true
        // Disable PencilKit's built-in undo manager — we use our own unified stack.
        canvas.undoManager?.removeAllActions()

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
            // Rebuild from the strokes rather than assigning the snapshot directly.
            // A PKDrawing carries PencilKit's internal version history, so restoring
            // an older snapshot (undo) could get merged with the canvas's newer state
            // on the next stroke, making the undone strokes reappear.
            canvas.drawing = PKDrawing(strokes: drawing.strokes)
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

            // Force PKCanvasView to rebuild its internal stroke hit-test index
            // so the eraser can find strokes loaded from a previous session.
            // Clear the undo manager afterward so the "load drawing" action
            // can't be undone (which would bulk-remove all loaded strokes).
            if !newDrawing.strokes.isEmpty {
                let coord = context.coordinator
                DispatchQueue.main.async {
                    coord.isRewriting = true
                    // Same reasoning as in makeUIView: round-trip through an empty
                    // drawing so PencilKit actually rebuilds its hit-test index.
                    let strokes = canvas.drawing.strokes
                    canvas.drawing = PKDrawing()
                    canvas.drawing = PKDrawing(strokes: strokes)
                    coord.isRewriting = false
                    canvas.undoManager?.removeAllActions()
                }
            } else {
                canvas.undoManager?.removeAllActions()
            }

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

        // Keep PKCanvasView's own scrolling disabled (reinforced every update)
        canvas.isScrollEnabled  = false
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 1.0
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

    static func dismantleUIView(_ canvas: PassThroughPKCanvasView, coordinator: Coordinator) {
        // When .id() changes, SwiftUI destroys the canvas. Save the current
        // drawing so strokes drawn since the last auto-save are not lost.
        guard !coordinator.currentChapterId.isEmpty,
              !canvas.drawing.strokes.isEmpty else { return }
        coordinator.vm.saveDrawing(canvas.drawing, for: coordinator.currentChapterId)
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

        /// No-op target for the finger tap gesture that blocks PencilKit's edit menu.
        @objc func eatTap() {}

        // MARK: Drawing delegate

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // A new stroke: anything added from here on is the user's, not a cut-off one.
            cutOff = nil
            // Capture the full annotation state before a stroke/erase begins.
            // This snapshot will be committed to the unified undo stack when
            // canvasViewDrawingDidChange fires with the completed stroke.
            guard !vm.isLassoActive else { return }
            vm.capturePreStrokeState()
        }

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

            // Auto Shapes: if PencilKit still commits the hand-drawn stroke that was cut
            // off when it snapped, drop it. The clean shape is what stays.
            if strokeAdded, let cutOff,
               Date().timeIntervalSince(cutOff.snappedAt) < 2,
               let last = canvasView.drawing.strokes.last,
               last.path.creationDate != cutOff.shapeDate {
                var strokes = canvasView.drawing.strokes
                strokes.removeLast()
                isRewriting = true
                canvasView.drawing = PKDrawing(strokes: strokes)
                isRewriting = false
                previousStrokeCount = strokes.count
                return
            }

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
                vm.commitPreStrokeUndo()
                canvasView.undoManager?.removeAllActions()
                save(canvasView.drawing)
                return
            }

            // Commit the pre-stroke snapshot to the undo stack for strokes and erases.
            vm.commitPreStrokeUndo()
            canvasView.undoManager?.removeAllActions()

            save(canvasView.drawing)
        }

        // MARK: - Auto Shapes (pen)

        /// Points of the stroke in progress, in canvas coordinates.
        private var shapePoints: [CGPoint] = []
        /// Where and when the pencil last moved noticeably (window coordinates).
        private var holdAnchor: CGPoint = .zero
        private var lastMoveTime = Date.distantPast
        /// A single pending check for "has the pencil been still long enough?".
        private var holdTask: Task<Void, Never>?
        /// Set when a stroke has just been snapped to a shape, so PencilKit committing the
        /// cut-off hand-drawn stroke afterwards can be told apart from the shape and
        /// dropped. Cleared when the next stroke begins.
        private var cutOff: (shapeDate: Date, snappedAt: Date)?

        private static let holdDuration: TimeInterval = 0.5
        /// Screen points of drift still counted as holding still.
        private static let holdTolerance: CGFloat = 4

        /// Called by PencilKit's drawing gesture as the pencil moves. Only does anything
        /// for the pen with Auto Shapes on.
        @objc func handleDrawingGesture(_ gesture: UIGestureRecognizer) {
            guard let canvas = canvas as? PassThroughPKCanvasView, canvas.autoShapeEnabled else {
                cancelHold()
                shapePoints = []
                return
            }
            switch gesture.state {
            case .began:
                shapePoints  = [gesture.location(in: canvas)]
                holdAnchor   = gesture.location(in: nil)
                lastMoveTime = Date()
                scheduleHoldCheck(after: Self.holdDuration)
            case .changed:
                let point = gesture.location(in: canvas)
                if let last = shapePoints.last, hypot(point.x - last.x, point.y - last.y) >= 0.5 {
                    shapePoints.append(point)
                }
                let screen = gesture.location(in: nil)
                if hypot(screen.x - holdAnchor.x, screen.y - holdAnchor.y) > Self.holdTolerance {
                    holdAnchor   = screen
                    lastMoveTime = Date()
                }
                if holdTask == nil { scheduleHoldCheck(after: Self.holdDuration) }
            default:   // ended, cancelled, failed
                cancelHold()
                shapePoints = []
            }
        }

        /// Checks once the pencil may have been still long enough; if it moved in the
        /// meantime, checks again when it could be.
        private func scheduleHoldCheck(after delay: TimeInterval) {
            holdTask?.cancel()
            holdTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.holdTask = nil
                let still = Date().timeIntervalSince(self.lastMoveTime)
                if still >= Self.holdDuration {
                    self.snapHeldStrokeToShape()
                } else {
                    self.scheduleHoldCheck(after: Self.holdDuration - still)
                }
            }
        }

        private func cancelHold() {
            holdTask?.cancel()
            holdTask = nil
        }

        /// The pencil has held still. If the stroke so far is a shape, swap it for a
        /// clean one right away, while the pencil is still down.
        private func snapHeldStrokeToShape() {
            guard let canvas,
                  (canvas as? PassThroughPKCanvasView)?.autoShapeEnabled == true,
                  [.began, .changed].contains(canvas.drawingGestureRecognizer.state),
                  let shape = ShapeRecognizer.recognize(shapePoints),
                  let tool = canvas.tool as? PKInkingTool
            else { return }

            let shapeDate = Date()
            let shapeStroke = Self.makeStroke(for: shape, ink: tool.ink, width: tool.width, date: shapeDate)
            let snapPoint = shapePoints.last ?? .zero
            shapePoints = []
            cutOff = (shapeDate: shapeDate, snappedAt: shapeDate)

            // End the hand-drawn stroke in progress. PencilKit drops it (or, if it commits
            // it, canvasViewDrawingDidChange removes it) and the clean shape takes its place.
            canvas.drawingGestureRecognizer.isEnabled = false
            canvas.drawingGestureRecognizer.isEnabled = true

            var strokes = canvas.drawing.strokes
            strokes.append(shapeStroke)
            isRewriting = true
            canvas.drawing = PKDrawing(strokes: strokes)
            isRewriting = false
            previousStrokeCount = strokes.count

            // One undo removes the shape, same as any other stroke.
            vm.commitPreStrokeUndo()
            canvas.undoManager?.removeAllActions()
            save(canvas.drawing)

            // A light tap on Apple Pencil Pro to confirm the snap.
            UICanvasFeedbackGenerator(view: canvas).pathCompleted(at: snapPoint)
        }

        /// A stroke tracing `shape` with the pen's current ink and width.
        private static func makeStroke(for shape: RecognizedShape, ink: PKInk,
                                       width: CGFloat, date: Date) -> PKStroke {
            let points = ShapeRecognizer.outline(of: shape).enumerated().map { i, location in
                PKStrokePoint(location:   location,
                              timeOffset: TimeInterval(i) * 0.005,
                              size:       CGSize(width: width, height: width),
                              opacity:    1,
                              force:      1,
                              azimuth:    0,
                              altitude:   .pi / 2)
            }
            return PKStroke(ink: ink,
                            path: PKStrokePath(controlPoints: points, creationDate: date),
                            transform: .identity)
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

        // MARK: Write-back helper

        private func rewrite(canvasView: PKCanvasView, replacing index: Int,
                             with stroke: PKStroke) {
            var strokes = canvasView.drawing.strokes
            guard index < strokes.count else { return }
            strokes[index] = stroke
            // Replace the stroke directly — our unified undo stack already
            // captured the pre-stroke state in canvasViewDidBeginUsingTool.
            isRewriting = true
            canvasView.drawing = PKDrawing(strokes: strokes)
            isRewriting = false
            previousStrokeCount = canvasView.drawing.strokes.count
        }
    }
}
