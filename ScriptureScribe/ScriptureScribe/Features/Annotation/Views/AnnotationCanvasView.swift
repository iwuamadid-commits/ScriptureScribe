//
//  AnnotationCanvasView.swift
//  ScriptureScribe
//
//  A transparent PencilKit drawing surface that overlays the Bible text.
//  It is placed INSIDE the parent ScrollView (same ZStack as the text),
//  so annotations scroll with the text rather than staying fixed on screen.
//
//  contentHeight must be passed in from the parent so the canvas is tall
//  enough to cover the entire chapter — not just the visible screen area.
//

import SwiftUI
import PencilKit

struct AnnotationCanvasView: UIViewRepresentable {

    @ObservedObject var vm: AnnotationViewModel
    let chapterId:    String
    let contentHeight: CGFloat   // must match the text content height

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
        }
        canvas.tool            = vm.pkTool
        canvas.drawingPolicy   = vm.allowFingerDrawing ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = vm.isAnnotating
    }

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let vm: AnnotationViewModel
        var currentChapterId = ""
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
