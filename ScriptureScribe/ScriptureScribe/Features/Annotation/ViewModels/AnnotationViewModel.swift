//
//  AnnotationViewModel.swift
//  ScriptureScribe
//
//  The brain of the Annotation Engine. It tracks:
//    • Which drawing tool is active (pen, highlighter, eraser, or lasso)
//    • What color and stroke size to use
//    • Whether guide lines are shown
//    • Whether the user is left- or right-handed (swaps toolbar side)
//    • Whether finger drawing is allowed (vs Apple Pencil only)
//
//  It also saves and loads each chapter's drawing to the device's Documents folder
//  so annotations survive app restarts. Firebase Storage upload is wired in Phase 6.
//

import SwiftUI
import PencilKit

@MainActor
final class AnnotationViewModel: ObservableObject {

    // MARK: - Tool

    enum DrawingTool: String, CaseIterable {
        case pen, highlighter, eraser, lasso

        var systemImage: String {
            switch self {
            case .pen:         return "pencil"
            case .highlighter: return "highlighter"
            case .eraser:      return "eraser"
            case .lasso:       return "lasso"
            }
        }

        var label: String {
            switch self {
            case .pen:         return "Pen"
            case .highlighter: return "Highlighter"
            case .eraser:      return "Eraser"
            case .lasso:       return "Lasso"
            }
        }
    }

    // MARK: - Guide Line Spacing

    enum GuideSpacing: String, CaseIterable {
        case narrow = "Narrow"
        case medium = "Medium"
        case wide   = "Wide"

        /// Pixels between each horizontal guide line.
        var lineInterval: CGFloat {
            switch self {
            case .narrow: return 28
            case .medium: return 44
            case .wide:   return 64
            }
        }
    }

    // MARK: - Published State

    @Published var isAnnotating    = false
    @Published var selectedTool:   DrawingTool = .pen
    @Published var selectedColor:  UIColor     = UIColor(red: 0.36, green: 0.54, blue: 0.42, alpha: 1) // sage green (matches Ivory theme)
    @Published var strokeWidth:    CGFloat     = 3
    @Published var showGuidelines  = false
    @Published var guideSpacing:   GuideSpacing = .medium
    @Published var showColorPicker = false

    // MARK: - Persisted User Preferences

    @AppStorage("isLeftHanded")       var isLeftHanded:       Bool = false
    @AppStorage("allowFingerDrawing") var allowFingerDrawing: Bool = true

    // MARK: - Callbacks from the Canvas View
    // These are set by AnnotationCanvasView.makeUIView so the toolbar
    // can trigger undo/redo/clear on the UIKit layer.

    var undoAction:        (() -> Void)?
    var redoAction:        (() -> Void)?
    var clearCanvasAction: (() -> Void)?

    // MARK: - Actions

    func toggleAnnotating() {
        isAnnotating.toggle()
    }

    func undo()        { undoAction?() }
    func redo()        { redoAction?() }
    func clearCanvas() { clearCanvasAction?() }

    // MARK: - The PencilKit Tool to Use Right Now

    /// Converts the selected tool + color + width into a PKTool that PencilKit understands.
    var pkTool: PKTool {
        switch selectedTool {
        case .pen:
            return PKInkingTool(.pen, color: selectedColor, width: strokeWidth)
        case .highlighter:
            // Semi-transparent wide marker stroke
            return PKInkingTool(.marker, color: selectedColor.withAlphaComponent(0.35), width: strokeWidth * 8)
        case .eraser:
            return PKEraserTool(.vector)
        case .lasso:
            return PKLassoTool()
        }
    }

    // MARK: - Local Persistence (Documents folder)

    /// Saves a chapter's drawing to the app's private Documents folder.
    /// The file name is based on the chapter ID (e.g. "GEN.1" → "annotation_GEN_1.pkdrawing").
    func saveDrawing(_ drawing: PKDrawing, for chapterId: String) {
        let url = drawingURL(for: chapterId)
        try? drawing.dataRepresentation().write(to: url, options: .atomic)
    }

    /// Loads a chapter's drawing from the Documents folder.
    /// Returns nil if the user has never annotated this chapter.
    func loadDrawing(for chapterId: String) -> PKDrawing? {
        let url = drawingURL(for: chapterId)
        guard
            FileManager.default.fileExists(atPath: url.path),
            let data    = try? Data(contentsOf: url),
            let drawing = try? PKDrawing(data: data)
        else { return nil }
        return drawing
    }

    // MARK: - Private

    private func drawingURL(for chapterId: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Make the ID safe to use as a filename
        let safeId = chapterId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        return docs.appendingPathComponent("annotation_\(safeId).pkdrawing")
    }
}
