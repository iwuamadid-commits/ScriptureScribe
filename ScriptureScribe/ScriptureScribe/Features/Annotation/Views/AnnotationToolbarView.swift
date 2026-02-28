//
//  AnnotationToolbarView.swift
//  ScriptureScribe
//
//  Minimal horizontal annotation toolbar (Noteful style, enhanced).
//  Icon-only design with saved colors row. Color and stroke settings appear
//  as a sheet when tapping the active tool again.
//
//  Color circle behavior:
//    • Single tap  → select that color
//    • Double tap  → select that color AND open the full color picker
//    • Long press  → delete from saved list
//  "+" button → opens the full color picker to pick and save a new color.
//

import SwiftUI

struct AnnotationToolbarView: View {

    @ObservedObject var vm: AnnotationViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel

    @State private var showColorPicker       = false
    @State private var showToolSettings      = false
    @State private var showPhotoSourcePicker = false
    @State private var showImagePicker       = false
    @State private var showClearConfirmation = false
    @State private var showPaywall           = false
    @State private var imagePickerSource     = UIImagePickerController.SourceType.photoLibrary

    // Drag-to-reorder state
    @State private var draggedColorIndex: Int?   = nil
    @State private var dragOffset:        CGFloat = 0
    @State private var dragSourceIndex:   Int     = 0

    var body: some View {
        HStack(spacing: 8) {

            // ── Tool buttons + camera ────────────────────────────────────
            HStack(spacing: 8) {
                ForEach(AnnotationViewModel.DrawingTool.allCases, id: \.self) { tool in
                    toolButton(for: tool)
                }

                // Camera button — sits right next to the hand tool
                Button {
                    showPhotoSourcePicker = true
                } label: {
                    Image(systemName: "camera")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                .accessibilityLabel("Add Photo")
            }

            // ── Saved Colors (inline, always visible, scrollable) ────────
            Divider()
                .frame(height: 28)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(vm.savedColors.enumerated()), id: \.element.stringValue) { index, savedColor in
                        let isSelected = savedColor.colorHex == vm.selectedColor.hexString
                        let isDragged  = draggedColorIndex == index

                        ZStack {
                            Circle().fill(Color(savedColor.uiColor))
                            Circle().strokeBorder(
                                isSelected
                                    ? themeManager.currentTheme.primary
                                    : Color.white.opacity(0.3),
                                lineWidth: isSelected ? 2.5 : 1.5
                            )
                        }
                        .frame(width: 28, height: 28)
                        .scaleEffect(isDragged ? 1.2 : (isSelected ? 1.25 : 1.0))
                        .shadow(color: .black.opacity(isDragged ? 0.25 : 0.15),
                                radius: isDragged ? 6 : 2,
                                y:      isDragged ? 2 : 0)
                        .offset(x: isDragged ? dragOffset : colorDisplacement(for: index))
                        .zIndex(isDragged ? 1 : 0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: draggedColorIndex)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: colorDisplacement(for: index))
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                            // Double-tap: select AND open color picker to replace this swatch
                            .onTapGesture(count: 2) {
                                vm.selectedColor = savedColor.uiColor
                                vm.saveCurrentToolSettings()
                                vm.pendingEditColorIndex = index
                                showColorPicker = true
                            }
                            // Single-tap: select, or open picker to replace if already selected
                            .onTapGesture(count: 1) {
                                if isSelected {
                                    vm.pendingEditColorIndex = index
                                    showColorPicker = true
                                } else {
                                    vm.selectedColor = savedColor.uiColor
                                    vm.saveCurrentToolSettings()
                                }
                            }
                            // Long press (0.4 s) → arm drag; pressing callback resets if finger
                            // lifts without any drag movement (lets context menu appear instead)
                            .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
                                if !pressing, draggedColorIndex == index, dragOffset == 0 {
                                    withAnimation { draggedColorIndex = nil }
                                }
                            }) {
                                dragSourceIndex = index
                                withAnimation { draggedColorIndex = index }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            // Horizontal drag — reorder only
                            // minimumDistance: 10_000 when not armed so normal taps are unaffected
                            .simultaneousGesture(
                                DragGesture(minimumDistance: isDragged ? 0 : 10_000)
                                    .onChanged { drag in
                                        guard draggedColorIndex == index else { return }
                                        dragOffset = drag.translation.width
                                    }
                                    .onEnded { _ in
                                        guard draggedColorIndex == index else { return }
                                        let proposed = proposedColorIndex()
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                            if proposed != dragSourceIndex {
                                                vm.moveColor(from: dragSourceIndex, to: proposed)
                                            }
                                            dragOffset        = 0
                                            draggedColorIndex = nil
                                        }
                                    }
                            )
                    }

                    // "+" button → add new color, or paywall if free user is at limit
                    Button {
                        let atLimit = !subscriptionVM.isPremium &&
                            vm.savedColors.count >= PremiumLimits.maxFreeSavedColors
                        if atLimit {
                            showPaywall = true
                        } else {
                            vm.pendingEditColorIndex = nil
                            showColorPicker = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                            .foregroundStyle(themeManager.currentTheme.primary)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Add new color")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity)
            .scrollDisabled(draggedColorIndex != nil)

            // ── Right: Undo / Redo / Settings ───────────────────────────
            HStack(spacing: 8) {
                Button { vm.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Undo")

                Button { vm.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Redo")

                settingsMenu
            }
            .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
        // Full Procreate-style color picker
        .sheet(isPresented: $showColorPicker) {
            ColorPickerWheelView(
                selectedColor: $vm.selectedColor,
                onSave: { color in
                    // If this is an "add new" operation, enforce the free-tier limit
                    let isAdding = vm.pendingEditColorIndex == nil
                    let atLimit  = !subscriptionVM.isPremium &&
                        vm.savedColors.count >= PremiumLimits.maxFreeSavedColors
                    if isAdding && atLimit {
                        showPaywall = true
                        return
                    }
                    vm.saveColorFromPicker(color)
                    vm.saveCurrentToolSettings()
                }
            )
        }
        // Photo source: take photo or choose from library
        .confirmationDialog("Add Photo", isPresented: $showPhotoSourcePicker) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    imagePickerSource = .camera
                    // Small delay lets the dialog fully dismiss before the sheet opens
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showImagePicker = true
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
                        .font(.title3)
                }
            }
            .frame(width: 44, height: 44)
            .foregroundStyle(tint)
            .background(
                isSelected
                    ? themeManager.currentTheme.primary.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .accessibilityLabel(tool.label)
    }

    // MARK: - Custom Highlighter Icon (Noteful-style chisel marker)

    private var highlighterMarkerIcon: some View {
        ZStack {
            // Cap / top band
            Path { p in
                p.move(to: CGPoint(x: 8, y: 0))
                p.addLine(to: CGPoint(x: 14, y: 0))
                p.addLine(to: CGPoint(x: 14, y: 3))
                p.addLine(to: CGPoint(x: 8, y: 3))
                p.closeSubpath()
            }
            .fill()
            .opacity(0.55)

            // Marker barrel (wide rectangular body)
            Path { p in
                p.move(to: CGPoint(x: 7, y: 3))
                p.addLine(to: CGPoint(x: 15, y: 3))
                p.addLine(to: CGPoint(x: 15, y: 15))
                p.addLine(to: CGPoint(x: 7, y: 15))
                p.closeSubpath()
            }
            .fill()

            // Chisel tip (angled flat nib)
            Path { p in
                p.move(to: CGPoint(x: 7, y: 15))
                p.addLine(to: CGPoint(x: 15, y: 15))
                p.addLine(to: CGPoint(x: 13, y: 20))
                p.addLine(to: CGPoint(x: 9, y: 20))
                p.closeSubpath()
            }
            .fill()
            .opacity(0.65)

            // Highlight stroke mark under the tip
            Path { p in
                p.move(to: CGPoint(x: 5, y: 21.5))
                p.addLine(to: CGPoint(x: 17, y: 21.5))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .opacity(0.3)
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
                .font(.title3)
                .frame(width: 44, height: 44)
                .foregroundStyle(themeManager.currentTheme.primary)
        }
        .accessibilityLabel("Settings")
    }

    // MARK: - Color Drag Helpers

    /// Width of one color slot: 28pt swatch + 6pt gap
    private let colorSlotWidth: CGFloat = 34

    /// Target index if the user releases the drag now.
    private func proposedColorIndex() -> Int {
        let move = Int(round(dragOffset / colorSlotWidth))
        return min(max(dragSourceIndex + move, 0), vm.savedColors.count - 1)
    }

    /// Horizontal displacement to apply to a non-dragged swatch so it slides
    /// out of the way to show where the dragged swatch will land.
    private func colorDisplacement(for index: Int) -> CGFloat {
        guard draggedColorIndex != nil else { return 0 }
        let proposed = proposedColorIndex()
        if dragSourceIndex < proposed, index > dragSourceIndex, index <= proposed {
            return -colorSlotWidth   // shift left
        }
        if dragSourceIndex > proposed, index >= proposed, index < dragSourceIndex {
            return colorSlotWidth    // shift right
        }
        return 0
    }
}
