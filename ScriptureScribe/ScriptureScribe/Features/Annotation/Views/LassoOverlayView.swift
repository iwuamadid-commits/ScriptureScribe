//
//  LassoOverlayView.swift
//  ScriptureScribe
//
//  Custom lasso overlay that selects photos, notes, and strokes.
//
//  Drawing: Routed through PKCanvasView — PencilKit draws a visible blue line
//           in real-time. The AnnotationCanvasView coordinator captures the
//           completed stroke, removes it, and publishes the points here.
//           This lets the canvas's PassThrough hitTest pass finger touches
//           through to BibleTextView for bookmarking.
//  Movement: Direct approach — selected strokes, photos, and notes are moved
//            incrementally each frame via moveLassoSelection(persist: false).
//            On release, positions are persisted once.
//  Action bar: Cut · Copy · Duplicate · Color · Delete
//

import SwiftUI
import PencilKit

struct LassoOverlayView: View {

    @ObservedObject var annotationVM: AnnotationViewModel
    @ObservedObject var notesVM:      NotesViewModel
    let chapterId: String
    let areaSize:  CGSize

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel

    @State private var showColorPicker = false
    @State private var showPaywall     = false
    @State private var lassoColor: UIColor = .black

    // Drag state
    @State private var isDragging = false
    @State private var lastDragTranslation: CGSize = .zero

    // Snapshot drag: render strokes as image for lag-free movement
    @State private var dragSnapshotImage: UIImage?
    @State private var dragSnapshotBounds: CGRect = .zero
    @State private var dragTotalDelta: CGSize = .zero
    @State private var dragOriginalStrokes: [PKStroke] = []

    /// Tracks which corner is being dragged for resize.
    @GestureState private var resizeCorner: ResizeCornerDrag = .zero

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    annotationVM.lassoState.clear()
                }
            selectionOverlay
        }
        .sheet(isPresented: $showColorPicker) {
            lassoColorPickerSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Selection Overlay

    private var selectionOverlay: some View {
        let box = annotationVM.lassoState.boundingBox

        let liveBox: CGRect = {
            guard abs(resizeCorner.rawX) > 0.1 || abs(resizeCorner.rawY) > 0.1 else { return box }
            let newW = max(40, box.width  + resizeCorner.rawX * resizeCorner.xMult)
            let newH = max(40, box.height + resizeCorner.rawY * resizeCorner.yMult)
            let shiftX = resizeCorner.rawX * (1 - resizeCorner.xMult) / 2
            let shiftY = resizeCorner.rawY * (1 - resizeCorner.yMult) / 2
            return CGRect(
                x: box.midX + shiftX - newW / 2,
                y: box.midY + shiftY - newH / 2,
                width: newW, height: newH
            )
        }()

        return ZStack {
            // Individual dashed outlines for each selected stroke (only when NOT dragging)
            if !isDragging {
                strokeOutlines
            }

            // Snapshot image of selected strokes (shown during drag for smooth movement)
            if isDragging, let snapshot = dragSnapshotImage {
                Image(uiImage: snapshot)
                    .position(
                        x: dragSnapshotBounds.midX + dragTotalDelta.width,
                        y: dragSnapshotBounds.midY + dragTotalDelta.height
                    )
                    .allowsHitTesting(false)
            }

            // Invisible drag surface
            Color.blue.opacity(0.001)
                .frame(width: liveBox.width, height: liveBox.height)
                .contentShape(Rectangle())
                .position(x: liveBox.midX, y: liveBox.midY)
                .gesture(groupDragGesture)

            // Dashed bounding rectangle
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .frame(width: liveBox.width, height: liveBox.height)
                .position(x: liveBox.midX, y: liveBox.midY)
                .allowsHitTesting(false)

            // Corner resize handles (hide during drag to avoid confusion)
            if !isDragging {
                resizeHandle(xMult: -1, yMult: -1, box: box)
                resizeHandle(xMult:  1, yMult: -1, box: box)
                resizeHandle(xMult: -1, yMult:  1, box: box)
                resizeHandle(xMult:  1, yMult:  1, box: box)
            }

            // Action bar
            actionBar
                .position(
                    x: liveBox.midX,
                    y: liveBox.minY - 28
                )
        }
    }

    // MARK: - Stroke Outlines

    @ViewBuilder
    private var strokeOutlines: some View {
        if let drawing = annotationVM.getDrawingAction?() {
            ForEach(annotationVM.lassoState.selectedStrokeIndices, id: \.self) { index in
                if index < drawing.strokes.count {
                    let bounds = drawing.strokes[index].renderBounds
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.blue.opacity(0.5),
                                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: bounds.width + 6, height: bounds.height + 6)
                        .position(x: bounds.midX, y: bounds.midY)
                }
            }
        }
    }

    // MARK: - Resize Corner Handle

    private func resizeHandle(xMult: CGFloat, yMult: CGFloat, box: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.blue, lineWidth: 1.5))
            .frame(width: 18, height: 18)
            .shadow(color: .black.opacity(0.2), radius: 2)
            .position(
                x: box.midX + (box.width / 2) * xMult,
                y: box.midY + (box.height / 2) * yMult
            )
            .gesture(
                DragGesture()
                    .updating($resizeCorner) { value, state, _ in
                        state = ResizeCornerDrag(
                            rawX: value.translation.width,
                            rawY: value.translation.height,
                            xMult: xMult,
                            yMult: yMult
                        )
                    }
                    .onEnded { value in
                        let rawX = value.translation.width
                        let rawY = value.translation.height
                        let oldW = box.width
                        let oldH = box.height
                        let newW = max(40, oldW + rawX * xMult)
                        let newH = max(40, oldH + rawY * yMult)
                        let scaleX = oldW > 0 ? newW / oldW : 1
                        let scaleY = oldH > 0 ? newH / oldH : 1
                        let scale  = (scaleX + scaleY) / 2
                        guard abs(scale - 1.0) > 0.01 else { return }
                        annotationVM.resizeLassoSelection(
                            scale:     scale,
                            chapterId: chapterId,
                            notesVM:   notesVM,
                            areaSize:  areaSize
                        )
                    }
            )
    }

    // MARK: - Noteful-Style Action Bar

    private var hasStrokes: Bool {
        !annotationVM.lassoState.selectedStrokeIndices.isEmpty
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            barButton("Cut") {
                withAnimation(.easeOut(duration: 0.25)) {
                    annotationVM.cutLassoSelection(
                        chapterId: chapterId, notesVM: notesVM, areaSize: areaSize
                    )
                }
            }
            barDivider

            barButton("Copy") {
                annotationVM.copyLassoSelection(
                    chapterId: chapterId, notesVM: notesVM, areaSize: areaSize
                )
                annotationVM.lassoState.clear()
            }
            barDivider

            barButton("Duplicate") {
                withAnimation(.easeOut(duration: 0.25)) {
                    annotationVM.duplicateLassoSelection(
                        chapterId: chapterId, notesVM: notesVM, areaSize: areaSize
                    )
                }
            }

            if hasStrokes {
                barDivider
                barButton("Color") {
                    if let drawing = annotationVM.getDrawingAction?(),
                       let firstIdx = annotationVM.lassoState.selectedStrokeIndices.first,
                       firstIdx < drawing.strokes.count {
                        lassoColor = drawing.strokes[firstIdx].ink.color
                    }
                    showColorPicker = true
                }
            }

            barDivider
            barButton("Delete", tint: .red) {
                withAnimation(.easeOut(duration: 0.25)) {
                    annotationVM.deleteLassoSelection(
                        chapterId: chapterId, notesVM: notesVM
                    )
                }
            }
        }
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }

    private func barButton(_ label: String, tint: Color = .primary,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 0.5, height: 20)
    }

    // MARK: - Color Picker Sheet

    private var isAtFreeLimit: Bool {
        !subscriptionVM.isPremium && annotationVM.savedColors.count >= PremiumLimits.maxFreeSavedColors
    }

    private var lassoColorPickerSheet: some View {
        NavigationStack {
            ColorPickerWheelView(
                selectedColor: $lassoColor,
                onAdd: { color in
                    if isAtFreeLimit {
                        showColorPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                            showPaywall = true
                        }
                        return
                    }
                    annotationVM.addSavedColor(color)
                    annotationVM.saveCurrentToolSettings()
                },
                onDone: { color in
                    lassoColor = color
                    annotationVM.recolorLassoSelection(
                        newColor:  color,
                        chapterId: chapterId
                    )
                    showColorPicker = false
                },
                vm: annotationVM,
                isAtLimit: isAtFreeLimit
            )
        }
    }

    // MARK: - Group Drag Gesture (snapshot-based for smooth movement)

    private var groupDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // First frame: snapshot strokes, hide originals, capture undo
                if !isDragging {
                    isDragging = true
                    annotationVM.captureLassoDragUndo(chapterId: chapterId, notesVM: notesVM)

                    // Snapshot selected strokes as an image for lag-free preview
                    if let snap = annotationVM.snapshotSelectedStrokes() {
                        dragSnapshotImage  = snap.image
                        dragSnapshotBounds = snap.bounds

                        // Capture original strokes before hiding them
                        if let drawing = annotationVM.getDrawingAction?() {
                            dragOriginalStrokes = annotationVM.lassoState.selectedStrokeIndices.compactMap {
                                $0 < drawing.strokes.count ? drawing.strokes[$0] : nil
                            }
                        }
                        annotationVM.hideSelectedStrokesFromCanvas()
                    }
                }

                // Track total delta for the snapshot image position
                dragTotalDelta = value.translation

                // Move photos and notes incrementally (they're lightweight SwiftUI views)
                let increment = CGSize(
                    width:  value.translation.width  - lastDragTranslation.width,
                    height: value.translation.height - lastDragTranslation.height
                )
                lastDragTranslation = value.translation
                annotationVM.movePhotosAndNotes(
                    by:        increment,
                    chapterId: chapterId,
                    notesVM:   notesVM,
                    areaSize:  areaSize
                )

                // Move the bounding box to track the drag
                annotationVM.lassoState.boundingBox = annotationVM.lassoState.boundingBox
                    .offsetBy(dx: increment.width, dy: increment.height)
            }
            .onEnded { _ in
                // Re-add strokes at final position
                if !dragOriginalStrokes.isEmpty {
                    annotationVM.restoreStrokesAfterDrag(
                        originalStrokes: dragOriginalStrokes,
                        delta: dragTotalDelta,
                        chapterId: chapterId
                    )
                }

                // Persist photo/note positions
                if !annotationVM.lassoState.selectedPhotoIds.isEmpty {
                    annotationVM.savePhotoAnnotations(for: chapterId)
                }
                if !annotationVM.lassoState.selectedNoteIds.isEmpty {
                    notesVM.persistNotes()
                }

                // Commit undo state
                annotationVM.commitLassoDragUndo()

                // Reset drag state
                isDragging          = false
                lastDragTranslation = .zero
                dragSnapshotImage   = nil
                dragSnapshotBounds  = .zero
                dragTotalDelta      = .zero
                dragOriginalStrokes = []
            }
    }
}

// MARK: - Resize Corner Drag State

private struct ResizeCornerDrag {
    var rawX:  CGFloat = 0
    var rawY:  CGFloat = 0
    var xMult: CGFloat = 1
    var yMult: CGFloat = 1
    static let zero = ResizeCornerDrag()
}
