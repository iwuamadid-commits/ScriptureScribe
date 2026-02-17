//
//  AnnotationCanvasView.swift
//  ScriptureScribe
//
//  A transparent drawing surface that floats on top of the Bible text.
//  Powered by Apple's PencilKit framework — the same technology used in the Notes app.
//
//  Key behaviours:
//    • Annotation mode OFF → canvas lets all touches pass through to the scrollable text below
//    • Annotation mode ON  → canvas captures touches for drawing (text scroll is blocked)
//    • Each Bible chapter has its own drawing, saved automatically to the device's storage
//    • Switching chapters automatically saves the old drawing and loads the new one
//    • Undo/Redo/Clear are triggered by the toolbar via callbacks on AnnotationViewModel
//

import SwiftUI
import PencilKit

struct AnnotationCanvasView: UIViewRepresentable {

    @ObservedObject var vm: AnnotationViewModel
    let chapterId: String

    // MARK: - Build the PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear   // transparent — Bible text shows through
        canvas.isOpaque = false
        canvas.tool = vm.pkTool
        canvas.drawingPolicy = vm.allowFingerDrawing ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = vm.isAnnotating
        canvas.delegate = context.coordinator

        // Keep a weak reference so the coordinator can save when chapters change
        context.coordinator.canvas = canvas
        context.coordinator.currentChapterId = chapterId

        // Load any drawing the user made in this chapter previously
        if let saved = vm.loadDrawing(for: chapterId) {
            canvas.drawing = saved
        }

        // Wire undo / redo / clear into the AnnotationViewModel
        // so the toolbar can trigger them with a simple vm.undo() call.
        vm.undoAction = { [weak canvas] in
            canvas?.undoManager?.undo()
        }
        vm.redoAction = { [weak canvas] in
            canvas?.undoManager?.redo()
        }
        vm.clearCanvasAction = { [weak canvas] in
            canvas?.drawing = PKDrawing()
        }

        return canvas
    }

    // MARK: - Sync Updates

    func updateUIView(_ canvas: PKCanvasView, context: Context) {

        // — Chapter changed: save old drawing, load new one —
        if context.coordinator.currentChapterId != chapterId {
            let previousId = context.coordinator.currentChapterId
            if !previousId.isEmpty {
                vm.saveDrawing(canvas.drawing, for: previousId)
            }
            canvas.drawing = vm.loadDrawing(for: chapterId) ?? PKDrawing()
            context.coordinator.currentChapterId = chapterId
        }

        // — Always stay in sync with the ViewModel —
        canvas.tool = vm.pkTool
        canvas.drawingPolicy = vm.allowFingerDrawing ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = vm.isAnnotating
    }

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(vm: vm)
    }

    /// Bridges PKCanvasViewDelegate callbacks back to AnnotationViewModel.
    class Coordinator: NSObject, PKCanvasViewDelegate {

        let vm: AnnotationViewModel
        var currentChapterId: String = ""
        weak var canvas: PKCanvasView?

        init(vm: AnnotationViewModel) {
            self.vm = vm
        }

        /// Called every time the user lifts their Pencil / finger after a stroke.
        /// We auto-save here so the drawing is never lost.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !currentChapterId.isEmpty else { return }
            let drawing   = canvasView.drawing
            let chapterId = currentChapterId
            Task { @MainActor in
                self.vm.saveDrawing(drawing, for: chapterId)
            }
        }
    }
}
