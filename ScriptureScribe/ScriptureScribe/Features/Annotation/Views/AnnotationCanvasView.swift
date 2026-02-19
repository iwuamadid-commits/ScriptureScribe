//
//  AnnotationCanvasView.swift
//  ScriptureScribe
//
//  A transparent PencilKit drawing surface that overlays the Bible text.
//  It is placed INSIDE the parent ScrollView (same ZStack as the text),
//  so annotations scroll with the text rather than staying fixed on screen.
//
//  contentHeight  — must match the text content height so the canvas covers
//                   the entire chapter, not just the visible screen area.
//  containerWidth — used to scale strokes proportionally when the layout
//                   switches (e.g. full-width → split-view). Without this,
//                   a stroke at x=700 on a 1024-wide canvas would be clipped
//                   when the canvas narrows to 512 in split view.
//

import SwiftUI
import PencilKit

struct AnnotationCanvasView: UIViewRepresentable {

    @ObservedObject var vm: AnnotationViewModel
    let chapterId:      String
    let contentHeight:  CGFloat   // must match the text content height
    let containerWidth: CGFloat   // used to scale strokes when layout changes

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque        = false
        canvas.tool            = vm.pkTool
        canvas.drawingPolicy   = vm.allowFingerDrawing ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = vm.isAnnotating
        canvas.delegate        = context.coordinator

        context.coordinator.canvas           = canvas
        context.coordinator.currentChapterId = chapterId
        context.coordinator.lastContainerWidth = containerWidth

        if let saved = vm.loadDrawing(for: chapterId) {
            canvas.drawing = saved
        }

        vm.undoAction        = { [weak canvas] in canvas?.undoManager?.undo() }
        vm.redoAction        = { [weak canvas] in canvas?.undoManager?.redo() }
        vm.clearCanvasAction = { [weak canvas] in canvas?.drawing = PKDrawing() }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Chapter changed → save old, load new
        if context.coordinator.currentChapterId != chapterId {
            let old = context.coordinator.currentChapterId
            if !old.isEmpty { vm.saveDrawing(canvas.drawing, for: old) }
            canvas.drawing = vm.loadDrawing(for: chapterId) ?? PKDrawing()
            context.coordinator.currentChapterId = chapterId
            // Reset width tracking for the new chapter so we don't mis-scale
            context.coordinator.lastContainerWidth = containerWidth
        }

        // Container width changed (e.g. full-width ↔ split-view) →
        // scale the drawing so strokes stay proportionally in the same place.
        let previousWidth = context.coordinator.lastContainerWidth
        if previousWidth > 1 && containerWidth > 1 &&
           abs(previousWidth - containerWidth) > 2 {
            let scale     = containerWidth / previousWidth
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let scaled    = canvas.drawing.transformed(using: transform)
            canvas.drawing = scaled
            vm.saveDrawing(scaled, for: chapterId)
        }
        context.coordinator.lastContainerWidth = containerWidth

        canvas.tool            = vm.pkTool
        canvas.drawingPolicy   = vm.allowFingerDrawing ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = vm.isAnnotating
    }

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let vm: AnnotationViewModel
        var currentChapterId   = ""
        var lastContainerWidth: CGFloat = 0
        weak var canvas: PKCanvasView?

        init(vm: AnnotationViewModel) { self.vm = vm }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !currentChapterId.isEmpty else { return }
            let drawing = canvasView.drawing
            let id      = currentChapterId
            Task { @MainActor in self.vm.saveDrawing(drawing, for: id) }
        }
    }
}
