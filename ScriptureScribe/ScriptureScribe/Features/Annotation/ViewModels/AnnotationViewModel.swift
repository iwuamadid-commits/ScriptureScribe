//
//  AnnotationViewModel.swift
//  ScriptureScribe
//

import Combine
import SwiftUI
import PencilKit

// MARK: - SavedColor

/// A color swatch saved to the annotation toolbar.
/// Defined at file scope so it can be referenced from Views without the AnnotationViewModel prefix.
struct SavedColor: Codable, Equatable {
    let colorHex: String
    let alpha: CGFloat
    var isHidden: Bool = false

    var uiColor: UIColor {
        guard let base = UIColor(hexString: colorHex) else { return .black }
        return base.withAlphaComponent(alpha)
    }

    init(color: UIColor) {
        self.colorHex = color.hexString
        var a: CGFloat = 0
        color.getRed(nil, green: nil, blue: nil, alpha: &a)
        self.alpha = a
    }

    // Stable ForEach ID — does NOT include isHidden so hide/show doesn't scramble animations
    var stringValue: String {
        "\(colorHex):\(alpha)"
    }

    // Legacy string init for migrating old UserDefaults format
    init?(stringValue: String) {
        let parts = stringValue.split(separator: ":")
        guard parts.count >= 2,
              let alpha = Double(parts[1])
        else { return nil }
        self.colorHex = String(parts[0])
        self.alpha = alpha
        self.isHidden = false
    }
}

@MainActor
final class AnnotationViewModel: ObservableObject {

    // MARK: - Enums

    enum DrawingTool: String, CaseIterable, Codable {
        case pen, highlighter, eraser, lasso, hand
        var systemImage: String {
            switch self {
            case .pen:         return "pencil"
            case .highlighter: return "highlighter"
            case .eraser:      return "eraser"
            case .lasso:       return "lasso"
            case .hand:        return "hand.raised.fill"
            }
        }
        var label: String { rawValue.capitalized }
    }

    enum EraserType: String, CaseIterable {
        case wholeLine = "Whole Line"   // removes the entire stroke you touch
        case pixel     = "Pixel"        // erases only where you drag, bit by bit
    }

    enum PenStyle: String, CaseIterable, Codable {
        case fountain    = "fountain"
        case calligraphy = "calligraphy"
        case crayon      = "crayon"

        var inkType: PKInkingTool.InkType {
            switch self {
            case .fountain:    return .pen
            case .calligraphy: return .fountainPen   // thick/thin based on stroke direction
            case .crayon:      return .crayon         // bold, waxy textured strokes
            }
        }

        var label: String {
            switch self {
            case .fountain:    return "Fountain"
            case .calligraphy: return "Calligraphy"
            case .crayon:      return "Crayon"
            }
        }
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

    // MARK: - Lasso Selection State

    struct LassoSelectionState {
        enum Phase { case idle, drawing, selected }

        var phase: Phase = .idle
        var path: [CGPoint] = []
        var selectedStrokeIndices: [Int] = []
        var selectedPhotoIds: Set<UUID> = []
        var selectedNoteIds: Set<String> = []
        var boundingBox: CGRect = .zero

        var hasSelection: Bool {
            !selectedStrokeIndices.isEmpty ||
            !selectedPhotoIds.isEmpty ||
            !selectedNoteIds.isEmpty
        }

        mutating func clear() {
            phase = .idle
            path = []
            selectedStrokeIndices = []
            selectedPhotoIds = []
            selectedNoteIds = []
            boundingBox = .zero
        }
    }

    // MARK: - Tool Settings Structs

    struct ToolSettings: Codable {
        var colorHex: String      // hex string for RGB (no alpha)
        var alpha: CGFloat        // alpha component (0.0 - 1.0)
        var strokeWidth: CGFloat
        var penStyle: PenStyle
        var straightLines: Bool

        enum CodingKeys: String, CodingKey {
            case colorHex, alpha, strokeWidth, penStyle, straightLines
        }

        var uiColor: UIColor {
            guard let base = UIColor(hexString: colorHex) else {
                return .black
            }
            return base.withAlphaComponent(alpha)
        }

        init(color: UIColor, strokeWidth: CGFloat,
             penStyle: PenStyle = .fountain, straightLines: Bool = false) {
            self.colorHex = color.hexString
            var a: CGFloat = 0
            color.getRed(nil, green: nil, blue: nil, alpha: &a)
            self.alpha = a
            self.strokeWidth = strokeWidth
            self.penStyle = penStyle
            self.straightLines = straightLines
        }

        init(colorHex: String, alpha: CGFloat, strokeWidth: CGFloat,
             penStyle: PenStyle = .fountain, straightLines: Bool = false) {
            self.colorHex = colorHex
            self.alpha = alpha
            self.strokeWidth = strokeWidth
            self.penStyle = penStyle
            self.straightLines = straightLines
        }

        // Backward-compatible decoder: older saved data won't have penStyle/straightLines
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            colorHex      = try  c.decode(String.self,    forKey: .colorHex)
            alpha         = try  c.decode(CGFloat.self,   forKey: .alpha)
            strokeWidth   = try  c.decode(CGFloat.self,   forKey: .strokeWidth)
            penStyle      = (try? c.decode(PenStyle.self, forKey: .penStyle))    ?? .fountain
            straightLines = (try? c.decode(Bool.self,     forKey: .straightLines)) ?? false
        }
    }

    // MARK: - Published State

    @Published var selectedTool:     DrawingTool  = .hand
    @Published var eraserType:       EraserType   = .wholeLine
    @Published var eraserSize:       CGFloat      = 15
    @Published var selectedColor:    UIColor      = UIColor(red: 0.36, green: 0.54, blue: 0.42, alpha: 1)
    @Published var strokeWidth:             CGFloat   = 3
    @Published var penStyle:               PenStyle  = .fountain
    @Published var highlighterStraightLines: Bool    = false
    @Published var showGuidelines    = false
    @Published var guideSpacing:     GuideSpacing = .medium
    @Published var showColorPicker   = false
    @Published var layoutMode:       LayoutMode   = .fullWidth
    @Published var lassoState = LassoSelectionState()
    /// Set by the canvas coordinator when a lasso stroke finishes on the PKCanvasView.
    /// LassoOverlayView observes this and runs the hit test.
    @Published var lassoPathPoints: [CGPoint] = []

    // Per-tool settings (each tool remembers its own color and stroke)
    @Published var toolSettings: [DrawingTool: ToolSettings] = [:]

    // Saved favorite colors (max 8)
    @Published var savedColors: [SavedColor] = []

    // Index of the saved-color swatch that opened the picker (nil = add new)
    // Stored on the ViewModel so closures always read the live value.
    var pendingEditColorIndex: Int? = nil

    // Favorite stroke sizes per tool (5 slots; nil = empty)
    @Published var penFavoriteSizes:         [Double?] = Array(repeating: nil, count: 5)
    @Published var highlighterFavoriteSizes: [Double?] = Array(repeating: nil, count: 5)
    @Published var eraserFavoriteSizes:      [Double?] = Array(repeating: nil, count: 5)

    // MARK: - Persisted Preferences

    @AppStorage("isLeftHanded")          var isLeftHanded:          Bool = false  // controls notebook side in split view
    @AppStorage("allowFingerDrawing")    var allowFingerDrawing:    Bool = true
    @AppStorage("useDoubleTapForNote")   var useDoubleTapForNote:   Bool = false

    // MARK: - Persistence Keys

    private let savedColorsKey    = "ss_savedAnnotationColors"      // legacy (migration only)
    private let savedColorsKeyV2  = "ss_savedAnnotationColors_v2"   // JSON format
    private let toolSettingsKey   = "ss_toolSettings"
    private let penFavSizesKey    = "ss_penFavSizes"
    private let hlFavSizesKey     = "ss_hlFavSizes"
    private let eraserFavSizesKey = "ss_eraserFavSizes"
    private let maxSavedColors    = 8

    // MARK: - Combine persistence subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // ── Restore layout mode ──────────────────────────────────────────
        if let raw  = UserDefaults.standard.string(forKey: "ss_layoutMode"),
           let mode = LayoutMode(rawValue: raw) {
            layoutMode = mode
        }

        // ── Restore eraser settings ──────────────────────────────────────
        if let raw  = UserDefaults.standard.string(forKey: "ss_eraserType"),
           let type = EraserType(rawValue: raw) {
            eraserType = type
        }
        let savedEraserSize = UserDefaults.standard.double(forKey: "ss_eraserSize")
        if savedEraserSize > 0 { eraserSize = CGFloat(savedEraserSize) }

        // ── Restore tool settings, saved colors, and favorite sizes ─────
        restoreToolSettings()
        loadSavedColors()
        loadFavoriteSizes()

        // ── Initialize with hand tool (pan/scroll mode by default) ───────
        loadToolSettings(for: .hand)

        // ── Subscribe: persist changes whenever they happen ──────────────
        $layoutMode
            .dropFirst()
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "ss_layoutMode") }
            .store(in: &cancellables)

        $eraserType
            .dropFirst()
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "ss_eraserType") }
            .store(in: &cancellables)

        $eraserSize
            .dropFirst()
            .sink { UserDefaults.standard.set(Double($0), forKey: "ss_eraserSize") }
            .store(in: &cancellables)
    }

    // MARK: - Canvas Callbacks (set by AnnotationCanvasView)

    var undoAction:        (() -> Void)?
    var redoAction:        (() -> Void)?
    var clearCanvasAction: (() -> Void)?
    var getDrawingAction:  (() -> PKDrawing)?
    var setDrawingAction:  ((PKDrawing) -> Void)?

    /// When true, the canvas delegate skips saving/OCR (used during lasso drag)
    var suppressCanvasSave = false

    /// The chapter currently displayed on the canvas (set by AnnotationCanvasView)
    var currentChapterId: String = ""

    /// Weak reference to NotesViewModel for undo/redo restoration
    weak var notesVMRef: NotesViewModel?

    // MARK: - Lasso Undo/Redo Stack

    struct LassoUndoSnapshot {
        let drawing: PKDrawing
        let photos: [PhotoAnnotation]?
        let notes: [UserNote]
        let chapterId: String
    }

    private var lassoUndoStack: [LassoUndoSnapshot] = []
    private var lassoRedoStack: [LassoUndoSnapshot] = []
    private var preDragSnapshot: LassoUndoSnapshot?
    private let maxUndoStackSize = 20

    private func captureLassoSnapshot(chapterId: String, notesVM: NotesViewModel?) -> LassoUndoSnapshot {
        LassoUndoSnapshot(
            drawing: getDrawingAction?() ?? PKDrawing(),
            photos: photoAnnotations[chapterId],
            notes: notesVM?.notes ?? notesVMRef?.notes ?? [],
            chapterId: chapterId
        )
    }

    private func pushLassoUndo(_ snapshot: LassoUndoSnapshot) {
        lassoUndoStack.append(snapshot)
        if lassoUndoStack.count > maxUndoStackSize {
            lassoUndoStack.removeFirst()
        }
        lassoRedoStack.removeAll()
    }

    private func restoreLassoSnapshot(_ snapshot: LassoUndoSnapshot) {
        // setDrawingAction uses isRewriting to safely bypass the delegate
        setDrawingAction?(snapshot.drawing)
        saveDrawing(snapshot.drawing, for: snapshot.chapterId)
        photoAnnotations[snapshot.chapterId] = snapshot.photos
        savePhotoAnnotations(for: snapshot.chapterId)
        if let notesVM = notesVMRef {
            notesVM.notes = snapshot.notes
            notesVM.persistNotes()
        }
    }

    /// Call before snapshot drag starts to capture pre-drag state.
    func captureLassoDragUndo(chapterId: String, notesVM: NotesViewModel) {
        notesVMRef = notesVM
        preDragSnapshot = captureLassoSnapshot(chapterId: chapterId, notesVM: notesVM)
    }

    /// Call after snapshot drag ends to commit the captured state to the undo stack.
    func commitLassoDragUndo() {
        if let snapshot = preDragSnapshot {
            pushLassoUndo(snapshot)
            preDragSnapshot = nil
        }
    }

    // MARK: - Computed Properties

    /// Returns true if the selected tool is a drawing tool (not hand or lasso)
    var isDrawingTool: Bool {
        selectedTool != .hand && selectedTool != .lasso
    }

    /// Returns true when the custom lasso overlay should be active
    var isLassoActive: Bool { selectedTool == .lasso }

    // MARK: - Actions

    /// Explicitly saves the current page's drawing to disk.
    /// Call this before any book/chapter switch to ensure strokes are not lost
    /// in the timing window between selectedBook changing and selectedChapter changing.
    func saveCurrentAnnotation() {
        guard !currentChapterId.isEmpty,
              let drawing = getDrawingAction?(),
              !drawing.strokes.isEmpty
        else { return }
        saveDrawing(drawing, for: currentChapterId)
    }

    func undo() {
        if let snapshot = lassoUndoStack.popLast() {
            let current = LassoUndoSnapshot(
                drawing: getDrawingAction?() ?? PKDrawing(),
                photos: photoAnnotations[snapshot.chapterId],
                notes: notesVMRef?.notes ?? [],
                chapterId: snapshot.chapterId
            )
            lassoRedoStack.append(current)
            restoreLassoSnapshot(snapshot)
            lassoState.clear()
        } else {
            undoAction?()
        }
    }

    func redo() {
        if let snapshot = lassoRedoStack.popLast() {
            let current = LassoUndoSnapshot(
                drawing: getDrawingAction?() ?? PKDrawing(),
                photos: photoAnnotations[snapshot.chapterId],
                notes: notesVMRef?.notes ?? [],
                chapterId: snapshot.chapterId
            )
            lassoUndoStack.append(current)
            restoreLassoSnapshot(snapshot)
            lassoState.clear()
        } else {
            redoAction?()
        }
    }
    func clearCanvas() {
        let chapterId = currentChapterId
        guard !chapterId.isEmpty else {
            clearCanvasAction?()
            return
        }
        let drawing = getDrawingAction?() ?? PKDrawing()
        let photos = photoAnnotations[chapterId] ?? []
        let chapterNotes = notesVMRef?.notes.filter { $0.chapterId == chapterId } ?? []
        let hasContent = !drawing.strokes.isEmpty || !photos.isEmpty || !chapterNotes.isEmpty

        // Capture current state for undo before clearing
        if hasContent {
            let undoSnapshot = LassoUndoSnapshot(
                drawing: drawing,
                photos: photoAnnotations[chapterId],
                notes: notesVMRef?.notes ?? [],
                chapterId: chapterId
            )
            pushLassoUndo(undoSnapshot)
        }

        // Clear drawing
        clearCanvasAction?()
        saveDrawing(PKDrawing(), for: chapterId)

        // Clear photos for this chapter
        if !photos.isEmpty {
            photoAnnotations[chapterId] = []
            savePhotoAnnotations(for: chapterId)
        }

        // Clear notes for this chapter
        if !chapterNotes.isEmpty, let notesVM = notesVMRef {
            notesVM.notes.removeAll { $0.chapterId == chapterId }
            notesVM.persistNotes()
        }
    }

    // MARK: - Tool Settings Management

    /// Returns default settings for each tool
    private func defaultSettings(for tool: DrawingTool) -> ToolSettings {
        switch tool {
        case .pen:
            return ToolSettings(
                color: UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1),
                strokeWidth: 3
            )
        case .highlighter:
            return ToolSettings(
                color: UIColor(red: 0.95, green: 0.9, blue: 0.3, alpha: 0.35),
                strokeWidth: 20
            )
        case .eraser:
            return ToolSettings(colorHex: "000000", alpha: 1, strokeWidth: 10)  // Not used
        case .lasso:
            return ToolSettings(colorHex: "000000", alpha: 1, strokeWidth: 1)   // Not used
        case .hand:
            return ToolSettings(colorHex: "000000", alpha: 1, strokeWidth: 1)   // Not used
        }
    }

    /// Load tool settings when switching tools.
    /// Color is intentionally NOT restored — it carries over from the previous tool
    /// so the user's active color stays consistent across pen/highlighter switches.
    func loadToolSettings(for tool: DrawingTool) {
        if tool != .lasso { lassoState.clear() }
        let settings = toolSettings[tool] ?? defaultSettings(for: tool)
        strokeWidth              = settings.strokeWidth
        penStyle                 = settings.penStyle
        highlighterStraightLines = settings.straightLines
    }

    /// Save current color/width to the active tool
    func saveCurrentToolSettings() {
        let settings = ToolSettings(
            color: selectedColor,
            strokeWidth: strokeWidth,
            penStyle: penStyle,
            straightLines: highlighterStraightLines
        )
        toolSettings[selectedTool] = settings
        persistToolSettings()
    }

    /// Persist tool settings to UserDefaults
    private func persistToolSettings() {
        let encoder = JSONEncoder()
        // UserDefaults property-list dictionaries require String keys,
        // so we convert DrawingTool → rawValue before saving.
        var stringKeyed: [String: String] = [:]
        for (tool, settings) in toolSettings {
            if let data = try? encoder.encode(settings) {
                stringKeyed[tool.rawValue] = data.base64EncodedString()
            }
        }
        UserDefaults.standard.set(stringKeyed, forKey: toolSettingsKey)
    }

    /// Restore tool settings from UserDefaults
    func restoreToolSettings() {
        guard let dict = UserDefaults.standard.dictionary(forKey: toolSettingsKey) as? [String: String] else { return }
        let decoder = JSONDecoder()
        for (key, value) in dict {
            guard let tool = DrawingTool(rawValue: key),
                  let data = Data(base64Encoded: value),
                  let settings = try? decoder.decode(ToolSettings.self, from: data)
            else { continue }
            toolSettings[tool] = settings
        }
    }

    // MARK: - Saved Colors Management

    /// Persist current savedColors to UserDefaults using JSON (v2 format).
    private func persistColors() {
        if let data = try? JSONEncoder().encode(savedColors) {
            UserDefaults.standard.set(data, forKey: savedColorsKeyV2)
        }
    }

    /// Load saved colors — tries v2 JSON first, migrates from legacy string-array if needed.
    func loadSavedColors() {
        if let data = UserDefaults.standard.data(forKey: savedColorsKeyV2),
           let colors = try? JSONDecoder().decode([SavedColor].self, from: data) {
            savedColors = colors
            return
        }
        // Migrate from legacy format
        if let strings = UserDefaults.standard.stringArray(forKey: savedColorsKey) {
            savedColors = strings.compactMap { SavedColor(stringValue: $0) }
            persistColors()
        }
    }

    /// Add a color to saved favorites (limit enforced at call site).
    func addSavedColor(_ color: UIColor) {
        let newColor = SavedColor(color: color)
        savedColors.removeAll { $0.colorHex == newColor.colorHex && $0.alpha == newColor.alpha }
        savedColors.insert(newColor, at: 0)
        if savedColors.count > maxSavedColors {
            savedColors = Array(savedColors.prefix(maxSavedColors))
        }
        persistColors()
    }

    /// Replace the saved color at the given index with a new color.
    func replaceColor(at index: Int, with color: UIColor) {
        guard index < savedColors.count else { return }
        savedColors[index] = SavedColor(color: color)
        selectedColor = color
        persistColors()
    }

    /// Delete the saved color at the given index.
    func deleteColor(at index: Int) {
        guard index < savedColors.count else { return }
        savedColors.remove(at: index)
        persistColors()
    }

    /// Duplicate the saved color at the given index, inserting the copy right after it.
    func duplicateColor(at index: Int) {
        guard index < savedColors.count else { return }
        var copy = savedColors[index]
        copy.isHidden = false
        savedColors.insert(copy, at: index + 1)
        if savedColors.count > maxSavedColors {
            savedColors = Array(savedColors.prefix(maxSavedColors))
        }
        persistColors()
    }

    /// Toggle the hidden state of the saved color at the given index.
    func toggleHideColor(at index: Int) {
        guard index < savedColors.count else { return }
        savedColors[index].isHidden.toggle()
        persistColors()
    }

    /// Reorder a saved color by moving it from one index to another.
    func moveColor(from source: Int, to destination: Int) {
        guard source != destination,
              source < savedColors.count,
              destination < savedColors.count else { return }
        let color = savedColors.remove(at: source)
        savedColors.insert(color, at: destination)
        persistColors()
    }

    /// Reorder using SwiftUI List's onMove IndexSet/destination — used by SavedColorsManagerView.
    func moveColors(fromOffsets: IndexSet, toOffset: Int) {
        savedColors.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persistColors()
    }

    // MARK: - Favorite Sizes Management

    func loadFavoriteSizes() {
        if let data = UserDefaults.standard.data(forKey: penFavSizesKey),
           let v = try? JSONDecoder().decode([Double?].self, from: data) {
            penFavoriteSizes = v
        }
        if let data = UserDefaults.standard.data(forKey: hlFavSizesKey),
           let v = try? JSONDecoder().decode([Double?].self, from: data) {
            highlighterFavoriteSizes = v
        }
        if let data = UserDefaults.standard.data(forKey: eraserFavSizesKey),
           let v = try? JSONDecoder().decode([Double?].self, from: data) {
            eraserFavoriteSizes = v
        }
    }

    func setFavoriteSize(_ size: CGFloat, at index: Int, for tool: DrawingTool) {
        switch tool {
        case .pen:
            penFavoriteSizes[index] = Double(size)
            if let data = try? JSONEncoder().encode(penFavoriteSizes) {
                UserDefaults.standard.set(data, forKey: penFavSizesKey)
            }
        case .highlighter:
            highlighterFavoriteSizes[index] = Double(size)
            if let data = try? JSONEncoder().encode(highlighterFavoriteSizes) {
                UserDefaults.standard.set(data, forKey: hlFavSizesKey)
            }
        case .eraser:
            eraserFavoriteSizes[index] = Double(size)
            if let data = try? JSONEncoder().encode(eraserFavoriteSizes) {
                UserDefaults.standard.set(data, forKey: eraserFavSizesKey)
            }
        default: break
        }
    }

    func clearFavoriteSize(at index: Int, for tool: DrawingTool) {
        switch tool {
        case .pen:
            penFavoriteSizes[index] = nil
            if let data = try? JSONEncoder().encode(penFavoriteSizes) {
                UserDefaults.standard.set(data, forKey: penFavSizesKey)
            }
        case .highlighter:
            highlighterFavoriteSizes[index] = nil
            if let data = try? JSONEncoder().encode(highlighterFavoriteSizes) {
                UserDefaults.standard.set(data, forKey: hlFavSizesKey)
            }
        case .eraser:
            eraserFavoriteSizes[index] = nil
            if let data = try? JSONEncoder().encode(eraserFavoriteSizes) {
                UserDefaults.standard.set(data, forKey: eraserFavSizesKey)
            }
        default: break
        }
    }

    // MARK: - Photo Annotations

    /// A photo the user has placed on a chapter's canvas.
    struct PhotoAnnotation: Identifiable {
        let id:            UUID
        var imageFileName: String   // filename only — image lives in the Documents folder
        var position:      CGPoint  // top-left corner, in canvas points
        var size:          CGSize   // width × height in canvas points
        var rotation:      Double       // degrees; 0 = upright
        var opacity:       Double       // 0.0 – 1.0; 1.0 = fully opaque
        var borderWidth:   CGFloat      // 0 = no border
        var borderColorHex: String      // RGB hex string, e.g. "FFFFFF"

        var uiImage: UIImage? {
            guard let url = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent(imageFileName),
                  let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
    }

    /// Persisted shape — UIImage isn't Codable, so we store only metadata here.
    private struct PhotoAnnotationRecord: Codable {
        let id: UUID; let imageFileName: String
        var positionX: Double; var positionY: Double
        var width: Double;     var height: Double
        var rotation:       Double
        var opacity:        Double
        var borderWidth:    Double
        var borderColorHex: String

        // Explicit init so the backward-compatible init(from:) can coexist.
        init(id: UUID, imageFileName: String,
             positionX: Double, positionY: Double,
             width: Double, height: Double,
             rotation: Double = 0, opacity: Double = 1.0,
             borderWidth: Double = 0, borderColorHex: String = "FFFFFF") {
            self.id = id; self.imageFileName = imageFileName
            self.positionX = positionX; self.positionY = positionY
            self.width = width; self.height = height
            self.rotation = rotation; self.opacity = opacity
            self.borderWidth = borderWidth; self.borderColorHex = borderColorHex
        }

        // Backward-compatible decoder: older saved records won't have the new fields.
        enum CodingKeys: String, CodingKey {
            case id, imageFileName, positionX, positionY, width, height
            case rotation, opacity, borderWidth, borderColorHex
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id             = try  c.decode(UUID.self,   forKey: .id)
            imageFileName  = try  c.decode(String.self, forKey: .imageFileName)
            positionX      = try  c.decode(Double.self, forKey: .positionX)
            positionY      = try  c.decode(Double.self, forKey: .positionY)
            width          = try  c.decode(Double.self, forKey: .width)
            height         = try  c.decode(Double.self, forKey: .height)
            rotation       = (try? c.decode(Double.self, forKey: .rotation))       ?? 0
            opacity        = (try? c.decode(Double.self, forKey: .opacity))        ?? 1.0
            borderWidth    = (try? c.decode(Double.self, forKey: .borderWidth))    ?? 0
            borderColorHex = (try? c.decode(String.self, forKey: .borderColorHex)) ?? "FFFFFF"
        }
    }

    /// Live photo annotations keyed by chapterId.
    @Published var photoAnnotations: [String: [PhotoAnnotation]] = [:]

    /// Set this from the toolbar after image picking; ReaderView will observe and save.
    @Published var pendingPhoto: UIImage? = nil

    /// The id of whichever photo is currently selected (shows handles + action bar).
    /// Setting to nil deselects everything.
    @Published var selectedPhotoId: UUID? = nil

    // MARK: Photo CRUD

    func addPhotoAnnotation(_ image: UIImage, for chapterId: String) {
        let uuid   = UUID()
        let safeId = chapterId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        let filename = "photo_\(safeId)_\(uuid.uuidString).jpg"

        // Write image file to disk
        if let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: docs.appendingPathComponent(filename), options: .atomic)
        }

        // Scale to 200pt wide, preserving aspect ratio
        let maxW: CGFloat = 200
        let aspect = image.size.width > 0 ? image.size.height / image.size.width : 1
        let size   = CGSize(width: maxW, height: maxW * aspect)

        // Place the photo near the centre of the visible screen area.
        // position is the top-left corner, so subtract half the photo size.
        let screen = UIScreen.main.bounds
        let centerPos = CGPoint(
            x: (screen.width  - size.width)  / 2,
            y: (screen.height - size.height) / 2
        )

        let annotation = PhotoAnnotation(
            id: uuid, imageFileName: filename,
            position: centerPos, size: size,
            rotation: 0, opacity: 1.0, borderWidth: 0, borderColorHex: "FFFFFF"
        )
        if photoAnnotations[chapterId] == nil { photoAnnotations[chapterId] = [] }
        photoAnnotations[chapterId]?.append(annotation)
        savePhotoAnnotations(for: chapterId)
    }

    func removePhotoAnnotation(id: UUID, for chapterId: String) {
        if let a = photoAnnotations[chapterId]?.first(where: { $0.id == id }),
           let docs = FileManager.default
               .urls(for: .documentDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(
                at: docs.appendingPathComponent(a.imageFileName)
            )
        }
        photoAnnotations[chapterId]?.removeAll { $0.id == id }
        savePhotoAnnotations(for: chapterId)
    }

    func movePhotoAnnotation(id: UUID, to position: CGPoint, for chapterId: String) {
        guard let idx = photoAnnotations[chapterId]?.firstIndex(where: { $0.id == id })
        else { return }
        photoAnnotations[chapterId]?[idx].position = position
        savePhotoAnnotations(for: chapterId)
    }

    func resizePhotoAnnotation(id: UUID, size: CGSize, for chapterId: String) {
        guard let idx = photoAnnotations[chapterId]?.firstIndex(where: { $0.id == id })
        else { return }
        photoAnnotations[chapterId]?[idx].size = size
        savePhotoAnnotations(for: chapterId)
    }

    func rotatePhotoAnnotation(id: UUID, rotation: Double, for chapterId: String) {
        guard let idx = photoAnnotations[chapterId]?.firstIndex(where: { $0.id == id })
        else { return }
        photoAnnotations[chapterId]?[idx].rotation = rotation
        savePhotoAnnotations(for: chapterId)
    }

    func updatePhotoStyle(id: UUID, opacity: Double, borderWidth: CGFloat,
                          borderColorHex: String, for chapterId: String) {
        guard let idx = photoAnnotations[chapterId]?.firstIndex(where: { $0.id == id })
        else { return }
        photoAnnotations[chapterId]?[idx].opacity        = opacity
        photoAnnotations[chapterId]?[idx].borderWidth    = borderWidth
        photoAnnotations[chapterId]?[idx].borderColorHex = borderColorHex
        savePhotoAnnotations(for: chapterId)
    }

    func duplicatePhotoAnnotation(id: UUID, for chapterId: String) {
        guard let original = photoAnnotations[chapterId]?.first(where: { $0.id == id })
        else { return }

        let newId = UUID()
        var newFilename = original.imageFileName

        // Copy the image file so the duplicate is fully independent
        if let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first {
            let safeId = chapterId
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ".", with: "_")
            newFilename = "photo_\(safeId)_\(newId.uuidString).jpg"
            let src = docs.appendingPathComponent(original.imageFileName)
            let dst = docs.appendingPathComponent(newFilename)
            try? FileManager.default.copyItem(at: src, to: dst)
        }

        let copy = PhotoAnnotation(
            id: newId, imageFileName: newFilename,
            position: CGPoint(x: original.position.x + 20, y: original.position.y + 20),
            size: original.size,
            rotation: original.rotation, opacity: original.opacity,
            borderWidth: original.borderWidth, borderColorHex: original.borderColorHex
        )
        if photoAnnotations[chapterId] == nil { photoAnnotations[chapterId] = [] }
        photoAnnotations[chapterId]?.append(copy)
        savePhotoAnnotations(for: chapterId)
    }

    /// Replace the stored image with a cropped/flipped version and update display size.
    func applyCropToPhoto(id: UUID, croppedImage: UIImage, for chapterId: String) {
        guard let idx = photoAnnotations[chapterId]?.firstIndex(where: { $0.id == id }),
              let docs = FileManager.default
                  .urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }

        let photo = photoAnnotations[chapterId]![idx]

        // Save new image as PNG (supports transparency from freehand crops)
        let safeId = chapterId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        let newFilename = "photo_\(safeId)_\(UUID().uuidString).png"
        if let data = croppedImage.pngData() {
            try? data.write(to: docs.appendingPathComponent(newFilename), options: .atomic)
        }

        // Remove old file
        try? FileManager.default.removeItem(
            at: docs.appendingPathComponent(photo.imageFileName)
        )

        // Preserve the current display width; adjust height for the new aspect ratio
        let aspect = croppedImage.size.width > 0
            ? croppedImage.size.height / croppedImage.size.width : 1.0
        let newSize = CGSize(width: photo.size.width, height: photo.size.width * aspect)

        photoAnnotations[chapterId]?[idx].imageFileName = newFilename
        photoAnnotations[chapterId]?[idx].size          = newSize
        savePhotoAnnotations(for: chapterId)
    }

    func loadPhotoAnnotations(for chapterId: String) {
        guard photoAnnotations[chapterId] == nil else { return } // already loaded
        let key = photoKey(for: chapterId)
        guard let data    = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([PhotoAnnotationRecord].self, from: data)
        else { photoAnnotations[chapterId] = []; return }

        // Build one annotation at a time so the type checker stays fast.
        var annotations: [PhotoAnnotation] = []
        for r in records {
            let pos  = CGPoint(x: r.positionX, y: r.positionY)
            let size = CGSize(width: r.width, height: r.height)
            let a = PhotoAnnotation(
                id: r.id, imageFileName: r.imageFileName,
                position: pos, size: size,
                rotation: r.rotation, opacity: r.opacity,
                borderWidth: CGFloat(r.borderWidth), borderColorHex: r.borderColorHex
            )
            annotations.append(a)
        }
        photoAnnotations[chapterId] = annotations
    }

    func savePhotoAnnotations(for chapterId: String) {
        let annotations = photoAnnotations[chapterId] ?? []
        // Build records one at a time so the type checker stays fast.
        var records: [PhotoAnnotationRecord] = []
        for a in annotations {
            let px = Double(a.position.x)
            let py = Double(a.position.y)
            let w  = Double(a.size.width)
            let h  = Double(a.size.height)
            let bw = Double(a.borderWidth)
            let r  = PhotoAnnotationRecord(
                id: a.id, imageFileName: a.imageFileName,
                positionX: px, positionY: py,
                width: w, height: h,
                rotation: a.rotation, opacity: a.opacity,
                borderWidth: bw, borderColorHex: a.borderColorHex
            )
            records.append(r)
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: photoKey(for: chapterId))
        }
    }

    private func photoKey(for chapterId: String) -> String {
        "ss_photos_" + chapterId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }

    // MARK: - PencilKit Tool

    var pkTool: PKTool {
        switch selectedTool {
        case .pen:
            return PKInkingTool(penStyle.inkType, color: selectedColor, width: strokeWidth)
        case .highlighter:
            return PKInkingTool(.marker, color: selectedColor.withAlphaComponent(0.35), width: strokeWidth)
        case .eraser:
            if eraserType == .wholeLine {
                return PKEraserTool(.vector)
            } else if #available(iOS 16.4, *) {
                return PKEraserTool(.bitmap, width: eraserSize)
            } else {
                return PKEraserTool(.bitmap)
            }
        case .lasso:
            // Visible blue line — PencilKit draws the lasso path in real-time.
            // The stroke is captured and removed after completion by the coordinator.
            return PKInkingTool(.pen, color: .systemBlue.withAlphaComponent(0.55), width: 2)
        case .hand:
            // Hand tool doesn't use PKTool — canvas will be non-interactive
            return PKInkingTool(.pen, color: .clear, width: 1)
        }
    }

    // MARK: - Annotation Indicator

    /// Returns true only when the chapter has real annotation content:
    /// drawn/handwritten strokes on either canvas, placed photos, or typed notes.
    /// (Typed notes are checked separately in ChapterSelectorRow via NotesViewModel.)
    func hasAnnotation(for chapterId: String) -> Bool {
        drawingHasStrokes(for: chapterId) ||
        drawingHasStrokes(for: "notebook_\(chapterId)") ||
        chapterHasPhotos(for: chapterId)
    }

    /// Check whether a saved drawing file contains at least one stroke.
    /// Uses a file-size proxy (< 100 bytes = empty PKDrawing) to avoid loading
    /// and parsing every file on every render of the chapter selector.
    private func drawingHasStrokes(for chapterId: String) -> Bool {
        let path = drawingURL(for: chapterId).path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size  = attrs[.size] as? Int else { return false }
        return size > 100   // an empty PKDrawing serialises to ~20-40 bytes
    }

    /// Check whether photos exist for this chapter (in memory if already loaded,
    /// otherwise fall back to the persisted UserDefaults record).
    private func chapterHasPhotos(for chapterId: String) -> Bool {
        if let photos = photoAnnotations[chapterId] { return !photos.isEmpty }
        let key = photoKey(for: chapterId)
        guard let data    = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([PhotoAnnotationRecord].self, from: data)
        else { return false }
        return !records.isEmpty
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

    // MARK: - Lasso Hit Testing

    /// Tests all photos, notes, and strokes against the closed lasso polygon.
    /// Rejects selections that cover more than 65% of the canvas (prevents
    /// accidental full-page lasso).
    func performLassoHitTest(
        areaSize: CGSize,
        chapterId: String,
        notes: [UserNote]
    ) {
        guard lassoState.path.count >= 3 else {
            lassoState.clear()
            return
        }

        // Reject overly large lasso — prevent full-background selection
        let polyBounds = lassoState.path.reduce(CGRect.null) { rect, pt in
            rect.union(CGRect(origin: pt, size: .zero))
        }
        let totalArea = areaSize.width * areaSize.height
        let polyArea  = polyBounds.width * polyBounds.height
        if totalArea > 0, polyArea / totalArea > 0.65 {
            lassoState.clear()
            return
        }

        selectedPhotoId = nil
        let polygon = lassoState.path
        var selectedStrokes: [Int] = []
        var selectedPhotos: Set<UUID> = []
        var selectedNotes: Set<String> = []
        var unionRect: CGRect = .null

        // 1. Check PKStrokes
        if let drawing = getDrawingAction?() {
            for (index, stroke) in drawing.strokes.enumerated() {
                let bounds = stroke.renderBounds
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                if pointInPolygon(point: center, polygon: polygon) {
                    selectedStrokes.append(index)
                    unionRect = unionRect.union(bounds)
                }
            }
        }

        // 2. Check PhotoAnnotations
        for photo in photoAnnotations[chapterId] ?? [] {
            let center = CGPoint(
                x: photo.position.x + photo.size.width / 2,
                y: photo.position.y + photo.size.height / 2
            )
            if pointInPolygon(point: center, polygon: polygon) {
                selectedPhotos.insert(photo.id)
                let photoRect = CGRect(origin: photo.position, size: photo.size)
                unionRect = unionRect.union(photoRect)
            }
        }

        // 3. Check Notes (convert normalized coords to absolute)
        for note in notes {
            let absX = note.positionX * areaSize.width
            let absY = note.positionY * areaSize.height
            let noteCenter = CGPoint(x: absX, y: absY)
            if pointInPolygon(point: noteCenter, polygon: polygon) {
                selectedNotes.insert(note.id)
                let noteRect = CGRect(x: absX - 70, y: absY - 20, width: 140, height: 40)
                unionRect = unionRect.union(noteRect)
            }
        }

        if selectedStrokes.isEmpty && selectedPhotos.isEmpty && selectedNotes.isEmpty {
            lassoState.clear()
        } else {
            lassoState.selectedStrokeIndices = selectedStrokes
            lassoState.selectedPhotoIds = selectedPhotos
            lassoState.selectedNoteIds = selectedNotes
            lassoState.boundingBox = unionRect.insetBy(dx: -12, dy: -12)
            lassoState.phase = .selected
        }
    }

    /// Ray-casting point-in-polygon algorithm.
    private func pointInPolygon(point: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y) {
                let intersectX = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
                if point.x < intersectX { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    // MARK: - Lasso Group Move

    func moveLassoSelection(
        by delta: CGSize,
        chapterId: String,
        notesVM: NotesViewModel,
        areaSize: CGSize,
        persist: Bool = true
    ) {
        // Move selected strokes
        if !lassoState.selectedStrokeIndices.isEmpty,
           let drawing = getDrawingAction?() {
            var allStrokes = drawing.strokes
            let transform = CGAffineTransform(translationX: delta.width, y: delta.height)
            for index in lassoState.selectedStrokeIndices where index < allStrokes.count {
                let movedDrawing = PKDrawing(strokes: [allStrokes[index]])
                    .transformed(using: transform)
                allStrokes[index] = movedDrawing.strokes[0]
            }
            let newDrawing = PKDrawing(strokes: allStrokes)
            // setDrawingAction uses isRewriting to safely bypass the delegate
            setDrawingAction?(newDrawing)
            if persist { saveDrawing(newDrawing, for: chapterId) }
        }

        // Move selected photos
        for photoId in lassoState.selectedPhotoIds {
            if let idx = photoAnnotations[chapterId]?.firstIndex(where: { $0.id == photoId }) {
                photoAnnotations[chapterId]?[idx].position.x += delta.width
                photoAnnotations[chapterId]?[idx].position.y += delta.height
            }
        }
        if persist && !lassoState.selectedPhotoIds.isEmpty {
            savePhotoAnnotations(for: chapterId)
        }

        // Move selected notes (convert pixel delta to normalized delta)
        for noteId in lassoState.selectedNoteIds {
            if let idx = notesVM.notes.firstIndex(where: { $0.id == noteId }) {
                notesVM.notes[idx].positionX += delta.width  / areaSize.width
                notesVM.notes[idx].positionY += delta.height / areaSize.height
            }
        }
        if persist && !lassoState.selectedNoteIds.isEmpty {
            notesVM.persistNotes()
        }

        // Shift bounding box
        lassoState.boundingBox = lassoState.boundingBox.offsetBy(dx: delta.width, dy: delta.height)
    }

    /// Save-only call — persists current positions without moving anything.
    func persistLassoPositions(chapterId: String, notesVM: NotesViewModel) {
        if !lassoState.selectedStrokeIndices.isEmpty,
           let drawing = getDrawingAction?() {
            saveDrawing(drawing, for: chapterId)
        }
        if !lassoState.selectedPhotoIds.isEmpty {
            savePhotoAnnotations(for: chapterId)
        }
        if !lassoState.selectedNoteIds.isEmpty {
            notesVM.persistNotes()
        }
    }

    // MARK: - Lasso Snapshot Drag (smooth stroke movement)

    /// Renders selected strokes as an image for smooth drag preview.
    func snapshotSelectedStrokes() -> (image: UIImage, bounds: CGRect)? {
        guard !lassoState.selectedStrokeIndices.isEmpty,
              let drawing = getDrawingAction?()
        else { return nil }

        let selectedStrokes = lassoState.selectedStrokeIndices.compactMap { index -> PKStroke? in
            index < drawing.strokes.count ? drawing.strokes[index] : nil
        }
        guard !selectedStrokes.isEmpty else { return nil }

        let selectedDrawing = PKDrawing(strokes: selectedStrokes)
        let bounds = selectedDrawing.bounds
        guard !bounds.isEmpty else { return nil }

        let paddedBounds = bounds.insetBy(dx: -4, dy: -4)
        let image = selectedDrawing.image(from: paddedBounds, scale: UIScreen.main.scale)
        return (image, paddedBounds)
    }

    /// Temporarily removes selected strokes from the canvas (for snapshot drag).
    func hideSelectedStrokesFromCanvas() {
        guard !lassoState.selectedStrokeIndices.isEmpty,
              let drawing = getDrawingAction?()
        else { return }

        var strokes = drawing.strokes
        for index in lassoState.selectedStrokeIndices.sorted().reversed() {
            guard index < strokes.count else { continue }
            strokes.remove(at: index)
        }
        // setDrawingAction uses isRewriting to safely bypass the delegate
        setDrawingAction?(PKDrawing(strokes: strokes))
    }

    /// Re-adds strokes (translated by delta) after snapshot drag ends.
    func restoreStrokesAfterDrag(
        originalStrokes: [PKStroke],
        delta: CGSize,
        chapterId: String
    ) {
        guard let drawing = getDrawingAction?() else { return }
        let transform = CGAffineTransform(translationX: delta.width, y: delta.height)
        var allStrokes = drawing.strokes
        var newIndices: [Int] = []
        for stroke in originalStrokes {
            let moved = PKDrawing(strokes: [stroke]).transformed(using: transform).strokes[0]
            newIndices.append(allStrokes.count)
            allStrokes.append(moved)
        }
        let newDrawing = PKDrawing(strokes: allStrokes)
        setDrawingAction?(newDrawing)
        saveDrawing(newDrawing, for: chapterId)
        lassoState.selectedStrokeIndices = newIndices
    }

    /// Moves only photos and notes (not strokes) — used during snapshot drag.
    func movePhotosAndNotes(
        by delta: CGSize,
        chapterId: String,
        notesVM: NotesViewModel,
        areaSize: CGSize
    ) {
        for photoId in lassoState.selectedPhotoIds {
            if let idx = photoAnnotations[chapterId]?.firstIndex(where: { $0.id == photoId }) {
                photoAnnotations[chapterId]?[idx].position.x += delta.width
                photoAnnotations[chapterId]?[idx].position.y += delta.height
            }
        }
        for noteId in lassoState.selectedNoteIds {
            if let idx = notesVM.notes.firstIndex(where: { $0.id == noteId }) {
                notesVM.notes[idx].positionX += delta.width  / areaSize.width
                notesVM.notes[idx].positionY += delta.height / areaSize.height
            }
        }
    }

    // MARK: - Lasso Group Resize

    func resizeLassoSelection(
        scale: CGFloat,
        chapterId: String,
        notesVM: NotesViewModel,
        areaSize: CGSize
    ) {
        notesVMRef = notesVM
        let undoSnapshot = captureLassoSnapshot(chapterId: chapterId, notesVM: notesVM)

        let box = lassoState.boundingBox
        let anchorX = box.midX
        let anchorY = box.midY

        // Resize selected strokes
        if !lassoState.selectedStrokeIndices.isEmpty,
           let drawing = getDrawingAction?() {
            var allStrokes = drawing.strokes
            // Translate to origin, scale, translate back
            let toOrigin = CGAffineTransform(translationX: -anchorX, y: -anchorY)
            let scaleT   = CGAffineTransform(scaleX: scale, y: scale)
            let toBack   = CGAffineTransform(translationX: anchorX, y: anchorY)
            let combined = toOrigin.concatenating(scaleT).concatenating(toBack)
            for index in lassoState.selectedStrokeIndices where index < allStrokes.count {
                let movedDrawing = PKDrawing(strokes: [allStrokes[index]])
                    .transformed(using: combined)
                allStrokes[index] = movedDrawing.strokes[0]
            }
            let newDrawing = PKDrawing(strokes: allStrokes)
            setDrawingAction?(newDrawing)
            saveDrawing(newDrawing, for: chapterId)
        }

        // Resize selected photos
        for photoId in lassoState.selectedPhotoIds {
            if let idx = photoAnnotations[chapterId]?.firstIndex(where: { $0.id == photoId }) {
                let photo = photoAnnotations[chapterId]![idx]
                let centerX = photo.position.x + photo.size.width / 2
                let centerY = photo.position.y + photo.size.height / 2
                let newCenterX = anchorX + (centerX - anchorX) * scale
                let newCenterY = anchorY + (centerY - anchorY) * scale
                let newW = max(40, photo.size.width * scale)
                let newH = max(40, photo.size.height * scale)
                photoAnnotations[chapterId]?[idx].size = CGSize(width: newW, height: newH)
                photoAnnotations[chapterId]?[idx].position = CGPoint(
                    x: newCenterX - newW / 2,
                    y: newCenterY - newH / 2
                )
            }
        }
        if !lassoState.selectedPhotoIds.isEmpty {
            savePhotoAnnotations(for: chapterId)
        }

        // Reposition selected notes (scale distance from anchor)
        for noteId in lassoState.selectedNoteIds {
            if let idx = notesVM.notes.firstIndex(where: { $0.id == noteId }) {
                let absX = notesVM.notes[idx].positionX * areaSize.width
                let absY = notesVM.notes[idx].positionY * areaSize.height
                let newX = anchorX + (absX - anchorX) * scale
                let newY = anchorY + (absY - anchorY) * scale
                notesVM.notes[idx].positionX = newX / areaSize.width
                notesVM.notes[idx].positionY = newY / areaSize.height
            }
        }
        if !lassoState.selectedNoteIds.isEmpty {
            notesVM.persistNotes()
        }

        // Update bounding box
        let newW = box.width * scale
        let newH = box.height * scale
        lassoState.boundingBox = CGRect(
            x: anchorX - newW / 2,
            y: anchorY - newH / 2,
            width: newW,
            height: newH
        )
        pushLassoUndo(undoSnapshot)
    }

    // MARK: - Lasso Clipboard

    /// Clipboard for strokes copied/cut from a lasso selection.
    struct LassoClipboard {
        var strokes: [PKStroke] = []
        var photoSnapshots: [(imageFileName: String, relativePos: CGPoint, size: CGSize,
                              rotation: Double, opacity: Double, borderWidth: CGFloat, borderColorHex: String)] = []
        var noteSnapshots: [(text: String, colorHex: String, relativeX: Double, relativeY: Double)] = []
        var isEmpty: Bool { strokes.isEmpty && photoSnapshots.isEmpty && noteSnapshots.isEmpty }
    }

    /// Shared clipboard for copy/cut/paste.
    var lassoClipboard = LassoClipboard()

    /// Copies selected items to the clipboard (strokes, photos, notes).
    func copyLassoSelection(chapterId: String, notesVM: NotesViewModel, areaSize: CGSize) {
        let box = lassoState.boundingBox
        var clipboard = LassoClipboard()

        // Copy strokes
        if let drawing = getDrawingAction?() {
            for index in lassoState.selectedStrokeIndices where index < drawing.strokes.count {
                clipboard.strokes.append(drawing.strokes[index])
            }
        }

        // Snapshot photos (relative to bounding box center)
        for photoId in lassoState.selectedPhotoIds {
            if let photo = photoAnnotations[chapterId]?.first(where: { $0.id == photoId }) {
                clipboard.photoSnapshots.append((
                    imageFileName: photo.imageFileName,
                    relativePos: CGPoint(x: photo.position.x - box.midX, y: photo.position.y - box.midY),
                    size: photo.size,
                    rotation: photo.rotation, opacity: photo.opacity,
                    borderWidth: photo.borderWidth, borderColorHex: photo.borderColorHex
                ))
            }
        }

        // Snapshot notes (relative to bounding box center, in absolute coords)
        for noteId in lassoState.selectedNoteIds {
            if let note = notesVM.notes.first(where: { $0.id == noteId }) {
                let absX = note.positionX * areaSize.width
                let absY = note.positionY * areaSize.height
                clipboard.noteSnapshots.append((
                    text: note.text,
                    colorHex: note.colorHex,
                    relativeX: absX - box.midX,
                    relativeY: absY - box.midY
                ))
            }
        }

        lassoClipboard = clipboard
    }

    /// Cuts selected items: copies to clipboard then deletes them.
    func cutLassoSelection(chapterId: String, notesVM: NotesViewModel, areaSize: CGSize) {
        copyLassoSelection(chapterId: chapterId, notesVM: notesVM, areaSize: areaSize)
        deleteLassoSelection(chapterId: chapterId, notesVM: notesVM)
    }

    /// Duplicates selected items: copies them and pastes with a small offset.
    /// The duplicated items remain selected so the user can immediately move them.
    func duplicateLassoSelection(chapterId: String, notesVM: NotesViewModel, areaSize: CGSize) {
        copyLassoSelection(chapterId: chapterId, notesVM: notesVM, areaSize: areaSize)

        let pasteCenter = CGPoint(x: lassoState.boundingBox.midX + 30,
                                   y: lassoState.boundingBox.midY + 30)

        // Track counts before paste so we can identify new items
        let strokesBefore = (getDrawingAction?())?.strokes.count ?? 0
        let photosBefore  = photoAnnotations[chapterId]?.count ?? 0
        let notesBefore   = notesVM.notes.count

        pasteLassoClipboard(at: pasteCenter, chapterId: chapterId,
                            notesVM: notesVM, areaSize: areaSize,
                            clearAfterPaste: false)

        // Point selection at the newly pasted items
        let strokesAfter = (getDrawingAction?())?.strokes.count ?? 0
        let photosAfter  = photoAnnotations[chapterId]?.count ?? 0
        let notesAfter   = notesVM.notes.count

        lassoState.selectedStrokeIndices = Array(strokesBefore..<strokesAfter)
        lassoState.selectedPhotoIds = Set(
            (photoAnnotations[chapterId] ?? []).suffix(photosAfter - photosBefore).map { $0.id }
        )
        lassoState.selectedNoteIds = Set(
            notesVM.notes.suffix(notesAfter - notesBefore).map { $0.id }
        )

        // Recalculate bounding box for the new items
        var unionRect: CGRect = .null
        if let drawing = getDrawingAction?() {
            for index in lassoState.selectedStrokeIndices where index < drawing.strokes.count {
                unionRect = unionRect.union(drawing.strokes[index].renderBounds)
            }
        }
        for photoId in lassoState.selectedPhotoIds {
            if let photo = photoAnnotations[chapterId]?.first(where: { $0.id == photoId }) {
                unionRect = unionRect.union(CGRect(origin: photo.position, size: photo.size))
            }
        }
        for noteId in lassoState.selectedNoteIds {
            if let note = notesVM.notes.first(where: { $0.id == noteId }) {
                let absX = note.positionX * areaSize.width
                let absY = note.positionY * areaSize.height
                unionRect = unionRect.union(CGRect(x: absX - 70, y: absY - 20, width: 140, height: 40))
            }
        }
        lassoState.boundingBox = unionRect.insetBy(dx: -12, dy: -12)
        lassoState.phase = .selected
    }

    /// Pastes clipboard contents centered at the given point.
    func pasteLassoClipboard(
        at center: CGPoint,
        chapterId: String,
        notesVM: NotesViewModel,
        areaSize: CGSize,
        clearAfterPaste: Bool = true
    ) {
        guard !lassoClipboard.isEmpty else { return }
        notesVMRef = notesVM
        let undoSnapshot = captureLassoSnapshot(chapterId: chapterId, notesVM: notesVM)

        // Paste strokes
        if !lassoClipboard.strokes.isEmpty, let drawing = getDrawingAction?() {
            let clipBounds = lassoClipboard.strokes.reduce(CGRect.null) { rect, stroke in
                rect.union(stroke.renderBounds)
            }
            let dx = center.x - clipBounds.midX
            let dy = center.y - clipBounds.midY
            let transform = CGAffineTransform(translationX: dx, y: dy)
            var allStrokes = drawing.strokes
            for stroke in lassoClipboard.strokes {
                let moved = PKDrawing(strokes: [stroke]).transformed(using: transform).strokes[0]
                allStrokes.append(moved)
            }
            let newDrawing = PKDrawing(strokes: allStrokes)
            setDrawingAction?(newDrawing)
            saveDrawing(newDrawing, for: chapterId)
        }

        // Paste photos
        for snap in lassoClipboard.photoSnapshots {
            let newId = UUID()
            let safeId = chapterId
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ".", with: "_")
            let newFilename = "photo_\(safeId)_\(newId.uuidString).jpg"
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let src = docs.appendingPathComponent(snap.imageFileName)
                let dst = docs.appendingPathComponent(newFilename)
                try? FileManager.default.copyItem(at: src, to: dst)
            }
            let photo = PhotoAnnotation(
                id: newId, imageFileName: newFilename,
                position: CGPoint(x: center.x + snap.relativePos.x, y: center.y + snap.relativePos.y),
                size: snap.size,
                rotation: snap.rotation, opacity: snap.opacity,
                borderWidth: snap.borderWidth, borderColorHex: snap.borderColorHex
            )
            if photoAnnotations[chapterId] == nil { photoAnnotations[chapterId] = [] }
            photoAnnotations[chapterId]?.append(photo)
        }
        if !lassoClipboard.photoSnapshots.isEmpty {
            savePhotoAnnotations(for: chapterId)
        }

        // Paste notes
        for snap in lassoClipboard.noteSnapshots {
            let absX = center.x + snap.relativeX
            let absY = center.y + snap.relativeY
            var note = UserNote(chapterId: chapterId, text: snap.text, createdAt: Date())
            note.positionX = absX / areaSize.width
            note.positionY = absY / areaSize.height
            note.colorHex  = snap.colorHex
            notesVM.notes.append(note)
        }
        if !lassoClipboard.noteSnapshots.isEmpty {
            notesVM.persistNotes()
        }

        pushLassoUndo(undoSnapshot)
        if clearAfterPaste {
            lassoState.clear()
        }
    }

    // MARK: - Lasso Recolor Strokes

    /// Changes the ink color of all selected strokes.
    func recolorLassoSelection(newColor: UIColor, chapterId: String) {
        guard !lassoState.selectedStrokeIndices.isEmpty,
              let drawing = getDrawingAction?()
        else { return }

        let undoSnapshot = captureLassoSnapshot(
            chapterId: chapterId,
            notesVM: notesVMRef
        )

        var allStrokes = drawing.strokes
        for index in lassoState.selectedStrokeIndices where index < allStrokes.count {
            let oldStroke = allStrokes[index]
            let newInk = PKInk(oldStroke.ink.inkType, color: newColor)
            let newStroke = PKStroke(
                ink: newInk,
                path: oldStroke.path,
                transform: oldStroke.transform,
                mask: oldStroke.mask
            )
            allStrokes[index] = newStroke
        }
        let newDrawing = PKDrawing(strokes: allStrokes)
        setDrawingAction?(newDrawing)
        saveDrawing(newDrawing, for: chapterId)
        pushLassoUndo(undoSnapshot)
    }

    // MARK: - Lasso Group Delete

    func deleteLassoSelection(chapterId: String, notesVM: NotesViewModel) {
        notesVMRef = notesVM
        let undoSnapshot = captureLassoSnapshot(chapterId: chapterId, notesVM: notesVM)

        // Delete selected strokes
        if !lassoState.selectedStrokeIndices.isEmpty,
           let drawing = getDrawingAction?() {
            var strokes = drawing.strokes
            for index in lassoState.selectedStrokeIndices.sorted().reversed() {
                guard index < strokes.count else { continue }
                strokes.remove(at: index)
            }
            let newDrawing = PKDrawing(strokes: strokes)
            setDrawingAction?(newDrawing)
            saveDrawing(newDrawing, for: chapterId)
        }

        // Delete selected photos (keep image files on disk for undo support)
        if !lassoState.selectedPhotoIds.isEmpty {
            photoAnnotations[chapterId]?.removeAll { lassoState.selectedPhotoIds.contains($0.id) }
            savePhotoAnnotations(for: chapterId)
        }

        // Delete selected notes
        for noteId in lassoState.selectedNoteIds {
            notesVM.notes.removeAll { $0.id == noteId }
        }
        if !lassoState.selectedNoteIds.isEmpty {
            notesVM.persistNotes()
        }

        pushLassoUndo(undoSnapshot)
        lassoState.clear()
    }
}
