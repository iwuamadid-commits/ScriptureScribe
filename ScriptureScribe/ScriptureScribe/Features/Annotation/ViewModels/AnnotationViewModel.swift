//
//  AnnotationViewModel.swift
//  ScriptureScribe
//

import Combine
import SwiftUI
import PencilKit

@MainActor
final class AnnotationViewModel: ObservableObject {

    // MARK: - Enums

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
        var label: String { rawValue.capitalized }
    }

    enum EraserType: String, CaseIterable {
        case wholeLine = "Whole Line"   // removes the entire stroke you touch
        case pixel     = "Pixel"        // erases only where you drag, bit by bit
    }

    enum GuideSpacing: String, CaseIterable {
        case narrow = "Narrow"
        case medium = "Medium"
        case wide   = "Wide"
        var lineInterval: CGFloat {
            switch self {
            case .narrow: return 28
            case .medium: return 44
            case .wide:   return 64
            }
        }
    }

    enum LayoutMode: String {
        case fullWidth  // Bible takes the full screen width (default)
        case splitView  // Bible on left, notebook on right
    }

    // MARK: - Published State

    @Published var isAnnotating      = false
    @Published var isToolbarCollapsed = false
    @Published var selectedTool:     DrawingTool  = .pen
    @Published var eraserType:       EraserType   = .wholeLine
    @Published var selectedColor:    UIColor      = UIColor(red: 0.36, green: 0.54, blue: 0.42, alpha: 1)
    @Published var strokeWidth:      CGFloat      = 3
    @Published var showGuidelines    = false
    @Published var guideSpacing:     GuideSpacing = .medium
    @Published var showColorPicker   = false
    @Published var layoutMode:       LayoutMode   = .fullWidth

    // MARK: - Persisted Preferences

    @AppStorage("isLeftHanded")       var isLeftHanded:       Bool = false
    @AppStorage("allowFingerDrawing") var allowFingerDrawing: Bool = true

    // MARK: - Canvas Callbacks (set by AnnotationCanvasView)

    var undoAction:        (() -> Void)?
    var redoAction:        (() -> Void)?
    var clearCanvasAction: (() -> Void)?

    // MARK: - Actions

    func toggleAnnotating()  { isAnnotating.toggle() }
    func undo()              { undoAction?() }
    func redo()              { redoAction?() }
    func clearCanvas()       { clearCanvasAction?() }

    // MARK: - PencilKit Tool

    var pkTool: PKTool {
        switch selectedTool {
        case .pen:
            return PKInkingTool(.pen, color: selectedColor, width: strokeWidth)
        case .highlighter:
            return PKInkingTool(.marker, color: selectedColor.withAlphaComponent(0.35), width: strokeWidth * 8)
        case .eraser:
            return eraserType == .wholeLine ? PKEraserTool(.vector) : PKEraserTool(.bitmap)
        case .lasso:
            return PKLassoTool()
        }
    }

    // MARK: - Annotation Indicator

    /// Returns true if a saved drawing file exists for the given chapter.
    /// Used to show a dot indicator on the chapter chip.
    func hasAnnotation(for chapterId: String) -> Bool {
        FileManager.default.fileExists(atPath: drawingURL(for: chapterId).path)
    }

    // MARK: - Persistence

    func saveDrawing(_ drawing: PKDrawing, for chapterId: String) {
        try? drawing.dataRepresentation().write(to: drawingURL(for: chapterId), options: .atomic)
    }

    func loadDrawing(for chapterId: String) -> PKDrawing? {
        let url = drawingURL(for: chapterId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let drawing = try? PKDrawing(data: data)
        else { return nil }
        return drawing
    }

    private func drawingURL(for chapterId: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let safeId = chapterId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        return docs.appendingPathComponent("annotation_\(safeId).pkdrawing")
    }
}
