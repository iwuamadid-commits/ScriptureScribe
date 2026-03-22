//
//  AnnotationToolbarView.swift
//  ScriptureScribe
//
//  Minimal horizontal annotation toolbar (Noteful style, enhanced).
//  Icon-only design with saved colors row. Color and stroke settings appear
//  as a sheet when tapping the active tool again.
//
//  Color circle behavior:
//    • Single tap on unselected  → select that color
//    • Single tap on selected    → open color picker (explore/modify)
//    • Long press (0.4 s)        → arm drag-to-reorder
//  "+" button → opens color picker (add new color via "+" inside picker).
//  Hidden colors are excluded from the toolbar but managed in Favorites.
//

import AVFoundation
import Photos
import SwiftUI

struct AnnotationToolbarView: View {

    @ObservedObject var vm: AnnotationViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    @State private var showColorPicker       = false
    @State private var showToolSettings      = false
    @State private var showPhotoSourcePicker = false
    @State private var showImagePicker       = false
    @State private var showClearConfirmation = false
    @State private var showPaywall           = false
    @State private var showPermissionAlert   = false
    @State private var permissionAlertMessage = ""
    @State private var imagePickerSource     = UIImagePickerController.SourceType.photoLibrary

    // Drag-to-reorder state (indices into visibleColors, not savedColors)
    @State private var draggedVisibleIndex:   Int?   = nil
    @State private var dragOffset:            CGFloat = 0
    @State private var dragSourceVisibleIndex: Int    = 0

    var body: some View {
        HStack(spacing: isCompact ? 4 : 8) {

            // ── Tool buttons + camera ────────────────────────────────────
            HStack(spacing: isCompact ? 4 : 8) {
                ForEach(AnnotationViewModel.DrawingTool.allCases, id: \.self) { tool in
                    toolButton(for: tool)
                }

                // Camera button — sits right next to the hand tool
                Button {
                    showPhotoSourcePicker = true
                } label: {
                    Image(systemName: "camera")
                        .font(isCompact ? .footnote : .title3)
                        .frame(width: isCompact ? 32 : 44, height: isCompact ? 32 : 44)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                .accessibilityLabel("Add Photo")
            }
            .coachMark("reader-annotation-toolbar")

            // ── Saved Colors (inline, always visible, scrollable) ────────
            Divider()
                .frame(height: isCompact ? 22 : 28)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(visibleColors.enumerated()), id: \.element.color.stringValue) { visibleIdx, item in
                        colorSwatch(visibleIdx: visibleIdx, item: item)
                    }

                    // "+" button → paywall if at free limit, otherwise open picker
                    Button {
                        if isAtFreeLimit {
                            showPaywall = true
                        } else {
                            vm.pendingEditColorIndex = nil
                            showColorPicker = true
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                                .foregroundStyle(themeManager.currentTheme.primary)
                            if isAtFreeLimit {
                                ProBadge()
                            }
                        }
                        .frame(height: 28)
                    }
                    .accessibilityLabel("Add new color")
                    .coachMark("reader-color-swatches")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity)
            .scrollDisabled(draggedVisibleIndex != nil)

            // ── Right: Undo / Redo / Settings ───────────────────────────
            HStack(spacing: isCompact ? 4 : 8) {
                Button { vm.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(isCompact ? .footnote : .title3)
                        .frame(width: isCompact ? 32 : 44, height: isCompact ? 32 : 44)
                }
                .accessibilityLabel("Undo")

                Button { vm.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(isCompact ? .footnote : .title3)
                        .frame(width: isCompact ? 32 : 44, height: isCompact ? 32 : 44)
                }
                .accessibilityLabel("Redo")

                settingsMenu
            }
            .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
        .padding(.horizontal, isCompact ? 8 : 16)
        .padding(.vertical, isCompact ? 4 : 8)
        .background(themeManager.currentTheme.surface)
        // Tool settings panel — pen style, eraser type, size favorites
        .sheet(isPresented: $showToolSettings) {
            ToolSettingsPanelView(
                vm: vm,
                tool: vm.selectedTool,
                onOpenColorPicker: {
                    showColorPicker = true
                }
            )
        }
        // Full color picker — wrapped in NavigationStack so the Favorites nav link works
        .sheet(isPresented: $showColorPicker) {
            NavigationStack {
                ColorPickerWheelView(
                    selectedColor: $vm.selectedColor,
                    onAdd: { color in
                        // Enforce free-tier limit when adding a new swatch.
                        // Dismiss picker first so we don't stack two sheets.
                        if isAtFreeLimit {
                            showColorPicker = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                                showPaywall = true
                            }
                            return
                        }
                        vm.addSavedColor(color)
                        vm.saveCurrentToolSettings()
                    },
                    onDone: { color in
                        if let idx = vm.pendingEditColorIndex {
                            vm.replaceColor(at: idx, with: color)
                        } else {
                            vm.selectedColor = color
                        }
                        vm.pendingEditColorIndex = nil
                        vm.saveCurrentToolSettings()
                    },
                    vm: vm,
                    isAtLimit: isAtFreeLimit
                )
            }
        }
        // Photo source: take photo or choose from library
        .confirmationDialog("Add Photo", isPresented: $showPhotoSourcePicker) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    switch status {
                    case .notDetermined:
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    imagePickerSource = .camera
                                    showImagePicker = true
                                } else {
                                    permissionAlertMessage = "Camera access is needed to take photos. You can enable it in Settings."
                                    showPermissionAlert = true
                                }
                            }
                        }
                    case .authorized:
                        imagePickerSource = .camera
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showImagePicker = true
                        }
                    default:
                        permissionAlertMessage = "Camera access is needed to take photos. You can enable it in Settings."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showPermissionAlert = true
                        }
                    }
                }
            }
            Button("Choose from Library") {
                imagePickerSource = .photoLibrary
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showImagePicker = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        // System image picker (camera or library)
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: imagePickerSource) { image in
                vm.pendingPhoto = image
            }
        }
        // Upgrade prompt when free user hits saved-color limit
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        // Confirmation before clearing the page
        .alert("Clear Page?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                vm.clearCanvas()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will erase everything on the current page. You can undo this action.")
        }
        // Permission denied — direct user to Settings
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(permissionAlertMessage)
        }
    }

    // MARK: - Tool Button

    private func toolButton(for tool: AnnotationViewModel.DrawingTool) -> some View {
        let isSelected = vm.selectedTool == tool
        let tint = isSelected
            ? themeManager.currentTheme.primary
            : themeManager.currentTheme.textSecondary

        return Button {
            if vm.selectedTool == tool {
                // Tool already selected → open settings panel
                if tool == .pen || tool == .highlighter || tool == .eraser {
                    showToolSettings = true
                }
            } else {
                // Switch to this tool and load its saved settings
                vm.selectedTool = tool
                vm.loadToolSettings(for: tool)
            }
        } label: {
            Group {
                if tool == .highlighter {
                    highlighterMarkerIcon
                } else {
                    Image(systemName: tool.systemImage)
                        .font(isCompact ? .footnote : .title3)
                }
            }
            .frame(width: isCompact ? 32 : 44, height: isCompact ? 32 : 44)
            .foregroundStyle(tint)
            .background(
                isSelected
                    ? themeManager.currentTheme.primary.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: isCompact ? 8 : 10)
            )
        }
        .accessibilityLabel(tool.label)
    }

    // MARK: - Custom Highlighter Icon (Stabilo-style wide marker)
    // Drawn vertically then rotated 45° — simple coordinates, clean result.
    // Cap (rounded dome) ends up at upper-right; chisel tip at lower-left.

    private var highlighterMarkerIcon: some View {
        ZStack {
            // ── Rotated marker body ─────────────────────────────────────────
            ZStack {
                // Cap + barrel: rounded dome on top, flat on bottom
                Path { p in
                    p.move(to: CGPoint(x: 7, y: 5))
                    p.addArc(center: CGPoint(x: 11, y: 5),
                             radius: 4,
                             startAngle: .degrees(180),
                             endAngle:   .degrees(0),
                             clockwise: false)         // dome faces outward
                    p.addLine(to: CGPoint(x: 15, y: 16))
                    p.addLine(to: CGPoint(x: 7,  y: 16))
                    p.closeSubpath()
                }
                .fill()

                // Chisel tip (trapezoid — narrows toward the nib end)
                Path { p in
                    p.move(to: CGPoint(x: 7,  y: 16))
                    p.addLine(to: CGPoint(x: 15, y: 16))
                    p.addLine(to: CGPoint(x: 13, y: 21))
                    p.addLine(to: CGPoint(x: 9,  y: 21))
                    p.closeSubpath()
                }
                .fill()
                .opacity(0.6)

            }
            .frame(width: 22, height: 22)
            .rotationEffect(.degrees(45))      // cap → upper-right, tip → lower-left
        }
        .frame(width: 22, height: 22)
    }

    // MARK: - Settings Menu

    private var settingsMenu: some View {
        Menu {

            // Notebook side (left or right in split-view)
            Section("Notebook Side") {
                Button { vm.isLeftHanded = false } label: {
                    Label("Right Side", systemImage: vm.isLeftHanded ? "" : "checkmark")
                }
                Button { vm.isLeftHanded = true } label: {
                    Label("Left Side", systemImage: vm.isLeftHanded ? "checkmark" : "")
                }
            }

            // Notes
            Section("Notes") {
                Button { vm.useDoubleTapForNote.toggle() } label: {
                    Label(
                        vm.useDoubleTapForNote ? "Double-Tap Note: On" : "Double-Tap Note: Off",
                        systemImage: vm.useDoubleTapForNote ? "hand.tap.fill" : "hand.tap"
                    )
                }
            }

            // Input
            Section("Input") {
                Button { vm.allowFingerDrawing.toggle() } label: {
                    Label(
                        vm.allowFingerDrawing ? "Finger: On" : "Finger: Off",
                        systemImage: vm.allowFingerDrawing ? "hand.draw.fill" : "hand.draw"
                    )
                }
            }

            // Canvas
            Section("Canvas") {
                Button(role: .destructive) { showClearConfirmation = true } label: {
                    Label("Clear Page", systemImage: "trash")
                }
            }

        } label: {
            Image(systemName: "gearshape")
                .font(isCompact ? .footnote : .title3)
                .frame(width: isCompact ? 32 : 44, height: isCompact ? 32 : 44)
                .foregroundStyle(themeManager.currentTheme.primary)
        }
        .accessibilityLabel("Settings")
    }

    // MARK: - Color Swatch

    /// Renders a single color swatch with tap, long-press, and drag gestures.
    /// Extracted into its own builder to prevent body type-check timeout.
    @ViewBuilder
    private func colorSwatch(visibleIdx: Int, item: (realIndex: Int, color: SavedColor)) -> some View {
        let isSelected:   Bool    = item.color.colorHex == vm.selectedColor.hexString
        let isDragged:    Bool    = draggedVisibleIndex == visibleIdx
        let displacement: CGFloat = isDragged ? dragOffset : colorDisplacement(for: visibleIdx)

        ZStack {
            Circle().fill(Color(item.color.uiColor))
            Circle().strokeBorder(
                isSelected ? themeManager.currentTheme.primary : Color.white.opacity(0.3),
                lineWidth: isSelected ? 2.5 : 1.5
            )
        }
        .frame(width: isCompact ? 22 : 28, height: isCompact ? 22 : 28)
        .scaleEffect(isDragged ? 1.2 : (isSelected ? 1.25 : 1.0))
        .shadow(color: .black.opacity(isDragged ? 0.25 : 0.15),
                radius: isDragged ? 6 : 2,
                y:      isDragged ? 2 : 0)
        .offset(x: displacement)
        .zIndex(isDragged ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: draggedVisibleIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: displacement)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        // Single-tap: select, or open picker if already selected
        .onTapGesture {
            if isSelected {
                vm.pendingEditColorIndex = item.realIndex
                showColorPicker = true
            } else {
                vm.selectedColor = item.color.uiColor
                vm.saveCurrentToolSettings()
            }
        }
        // Long press (0.4 s) → arm drag
        .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
            if !pressing, draggedVisibleIndex == visibleIdx, dragOffset == 0 {
                withAnimation { draggedVisibleIndex = nil }
            }
        }) {
            dragSourceVisibleIndex = visibleIdx
            withAnimation { draggedVisibleIndex = visibleIdx }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        // Horizontal drag — reorder only
        .simultaneousGesture(
            DragGesture(minimumDistance: isDragged ? 0 : 10_000)
                .onChanged { drag in
                    guard draggedVisibleIndex == visibleIdx else { return }
                    dragOffset = drag.translation.width
                }
                .onEnded { _ in
                    guard draggedVisibleIndex == visibleIdx else { return }
                    let proposedVisible = proposedVisibleIndex()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        if proposedVisible != dragSourceVisibleIndex {
                            let fromReal = visibleColors[dragSourceVisibleIndex].realIndex
                            let toReal   = visibleColors[proposedVisible].realIndex
                            vm.moveColor(from: fromReal, to: toReal)
                        }
                        dragOffset          = 0
                        draggedVisibleIndex = nil
                    }
                }
        )
    }

    // MARK: - Helpers

    /// True when a free user has reached the saved-color cap.
    private var isAtFreeLimit: Bool {
        !subscriptionVM.isPremium && vm.savedColors.count >= PremiumLimits.maxFreeSavedColors
    }

    // MARK: - Color Drag Helpers

    /// Non-hidden colors paired with their real index in vm.savedColors.
    private var visibleColors: [(realIndex: Int, color: SavedColor)] {
        vm.savedColors.enumerated().compactMap { offset, element in
            element.isHidden ? nil : (realIndex: offset, color: element)
        }
    }

    /// Width of one color slot: 28pt swatch + 6pt gap
    private let colorSlotWidth: CGFloat = 34

    /// Proposed visible index if the user releases the drag now.
    private func proposedVisibleIndex() -> Int {
        let move = Int(round(dragOffset / colorSlotWidth))
        return min(max(dragSourceVisibleIndex + move, 0), visibleColors.count - 1)
    }

    /// Horizontal displacement to apply to a non-dragged swatch so it slides
    /// out of the way to show where the dragged swatch will land.
    /// `index` is the visible index (position within visibleColors).
    private func colorDisplacement(for index: Int) -> CGFloat {
        guard draggedVisibleIndex != nil else { return 0 }
        let proposed = proposedVisibleIndex()
        if dragSourceVisibleIndex < proposed, index > dragSourceVisibleIndex, index <= proposed {
            return -colorSlotWidth   // shift left
        }
        if dragSourceVisibleIndex > proposed, index >= proposed, index < dragSourceVisibleIndex {
            return colorSlotWidth    // shift right
        }
        return 0
    }
}
