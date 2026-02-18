//
//  AnnotationToolbarView.swift
//  ScriptureScribe
//
//  Freely draggable floating toolbar for the annotation engine.
//
//  How it moves:
//    • vm.toolbarPosition holds the committed offset from the overlay's top-left.
//    • A @GestureState (drag) adds live translation while the finger is down.
//    • The combined offset is applied to the whole view via .offset().
//    • The drag handle (≡ strip) is the ONLY hit area for dragging, so all
//      buttons and menus inside still respond to taps normally.
//
//  Orientation:
//    • Vertical (default): standard tall pill, one button per row.
//    • Horizontal: same buttons laid out left-to-right.
//
//  Notebook side (left/right-handed):
//    • Controlled from the settings menu inside this toolbar.
//    • Changes the side the notebook panel appears on in split-view mode.
//

import SwiftUI

struct AnnotationToolbarView: View {

    @ObservedObject var vm: AnnotationViewModel
    @EnvironmentObject var themeManager: ThemeManager

    // Live drag offset while the user is dragging the handle
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        content
            // Apply committed position + live drag as an offset from the top-left
            .offset(
                x: vm.toolbarPosition.x + drag.width,
                y: vm.toolbarPosition.y + drag.height
            )
            .sheet(isPresented: $vm.showColorPicker) {
                ColorPickerWheelView(selectedColor: $vm.selectedColor)
                    .presentationDetents([.large])
            }
    }

    // MARK: - Collapsed vs Expanded

    @ViewBuilder
    private var content: some View {
        if vm.isToolbarCollapsed {
            collapsedButton
        } else {
            expandedPanel
        }
    }

    // MARK: - Collapsed State

    private var collapsedButton: some View {
        VStack(spacing: 4) {
            dragHandleStrip   // drag here when collapsed
            Button { vm.isToolbarCollapsed = false } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.title)
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("Expand toolbar")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }

    // MARK: - Expanded Panel (Vertical or Horizontal)

    @ViewBuilder
    private var expandedPanel: some View {
        if vm.isToolbarHorizontal {
            horizontalPanel
        } else {
            verticalPanel
        }
    }

    // ── Vertical Layout ──────────────────────────────────────────────────

    private var verticalPanel: some View {
        VStack(spacing: 4) {
            dragHandleStrip

            toolbarButton(systemImage: "chevron.right", label: "Collapse", isAccent: true) {
                vm.isToolbarCollapsed = true
            }
            toolbarButton(systemImage: "xmark.circle.fill", label: "Done", isAccent: true) {
                vm.toggleAnnotating()
            }

            vDivider

            ForEach(AnnotationViewModel.DrawingTool.allCases, id: \.self) { tool in
                VStack(spacing: 0) {
                    toolbarButton(systemImage: tool.systemImage,
                                  label: tool.label,
                                  isSelected: vm.selectedTool == tool) {
                        vm.selectedTool = tool
                    }
                    if tool == .eraser && vm.selectedTool == .eraser {
                        eraserTypePicker(horizontal: false)
                    }
                }
            }

            vDivider

            colorSwatch

            strokeSliderVertical

            vDivider

            guidelineButton
            if vm.showGuidelines { guideSpacingMenu }

            vDivider

            toolbarButton(systemImage: "arrow.uturn.backward", label: "Undo") { vm.undo() }
            toolbarButton(systemImage: "arrow.uturn.forward",  label: "Redo") { vm.redo() }

            vDivider

            settingsMenu
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    // ── Horizontal Layout ────────────────────────────────────────────────

    private var horizontalPanel: some View {
        HStack(spacing: 4) {
            dragHandleStripHorizontal

            toolbarButton(systemImage: "chevron.down", label: "Collapse", isAccent: true) {
                vm.isToolbarCollapsed = true
            }
            toolbarButton(systemImage: "xmark.circle.fill", label: "Done", isAccent: true) {
                vm.toggleAnnotating()
            }

            hDivider

            ForEach(AnnotationViewModel.DrawingTool.allCases, id: \.self) { tool in
                HStack(spacing: 0) {
                    toolbarButton(systemImage: tool.systemImage,
                                  label: tool.label,
                                  isSelected: vm.selectedTool == tool) {
                        vm.selectedTool = tool
                    }
                    if tool == .eraser && vm.selectedTool == .eraser {
                        eraserTypePicker(horizontal: true)
                    }
                }
            }

            hDivider

            colorSwatch

            strokeSliderHorizontal

            hDivider

            guidelineButton
            if vm.showGuidelines { guideSpacingMenu }

            hDivider

            toolbarButton(systemImage: "arrow.uturn.backward", label: "Undo") { vm.undo() }
            toolbarButton(systemImage: "arrow.uturn.forward",  label: "Redo") { vm.redo() }

            hDivider

            settingsMenu
        }
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    // MARK: - Shared Sub-Views

    private var colorSwatch: some View {
        Button { vm.showColorPicker = true } label: {
            Circle()
                .fill(Color(vm.selectedColor))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("Choose color")
    }

    private var strokeSliderVertical: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(Color(vm.selectedColor))
                .frame(width: min(vm.strokeWidth * 2.5, 22),
                       height: min(vm.strokeWidth * 2.5, 22))
                .frame(width: 22, height: 22)
            Slider(value: $vm.strokeWidth, in: 1...12, step: 0.5)
                .frame(width: 36)
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 100)
                .tint(Color(vm.selectedColor))
        }
    }

    private var strokeSliderHorizontal: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(vm.selectedColor))
                .frame(width: min(vm.strokeWidth * 2.0, 18),
                       height: min(vm.strokeWidth * 2.0, 18))
                .frame(width: 18, height: 18)
            Slider(value: $vm.strokeWidth, in: 1...12, step: 0.5)
                .frame(width: 80)
                .tint(Color(vm.selectedColor))
        }
    }

    private var guidelineButton: some View {
        toolbarButton(
            systemImage: vm.showGuidelines ? "line.3.horizontal" : "line.horizontal.3",
            label:       "Guidelines",
            isSelected:  vm.showGuidelines
        ) {
            vm.showGuidelines.toggle()
        }
    }

    private var guideSpacingMenu: some View {
        Menu {
            ForEach(AnnotationViewModel.GuideSpacing.allCases, id: \.self) { s in
                Button { vm.guideSpacing = s } label: {
                    Label(s.rawValue, systemImage: vm.guideSpacing == s ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16))
                .frame(width: 44, height: 36)
                .foregroundStyle(themeManager.currentTheme.primary)
        }
    }

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

            // Toolbar orientation
            Section("Toolbar Layout") {
                Button { vm.isToolbarHorizontal = false } label: {
                    Label("Vertical",   systemImage: vm.isToolbarHorizontal ? "" : "checkmark")
                }
                Button { vm.isToolbarHorizontal = true } label: {
                    Label("Horizontal", systemImage: vm.isToolbarHorizontal ? "checkmark" : "")
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
                Button(role: .destructive) { vm.clearCanvas() } label: {
                    Label("Clear Page", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
                .foregroundStyle(themeManager.currentTheme.primary)
        }
    }

    // MARK: - Eraser Type Sub-Picker

    private func eraserTypePicker(horizontal: Bool) -> some View {
        let buttons = ForEach(AnnotationViewModel.EraserType.allCases, id: \.self) { type in
            Button { vm.eraserType = type } label: {
                Text(type == .wholeLine ? "Line" : "Pixel")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 38, height: 26)
                    .background(
                        vm.eraserType == type
                            ? themeManager.currentTheme.primary.opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .foregroundStyle(
                        vm.eraserType == type
                            ? themeManager.currentTheme.primary
                            : themeManager.currentTheme.textSecondary
                    )
            }
        }
        return Group {
            if horizontal {
                HStack(spacing: 2) { buttons }.padding(.trailing, 4)
            } else {
                VStack(spacing: 2) { buttons }.padding(.bottom, 4)
            }
        }
    }

    // MARK: - Drag Handle

    /// Vertical layout: a small ≡ pill at the very top of the toolbar.
    /// This is the ONLY drag target so buttons below still respond to taps.
    private var dragHandleStrip: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.gray.opacity(0.45))
            .frame(width: 28, height: 4)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .contentShape(Rectangle().size(CGSize(width: 44, height: 20)))
            .frame(width: 44, height: 20)
            .gesture(handleDragGesture)
    }

    /// Horizontal layout: a vertical ≡ pill on the far left of the toolbar.
    private var dragHandleStripHorizontal: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.gray.opacity(0.45))
            .frame(width: 4, height: 28)
            .padding(.leading, 4)
            .padding(.trailing, 2)
            .contentShape(Rectangle().size(CGSize(width: 20, height: 44)))
            .frame(width: 20, height: 44)
            .gesture(handleDragGesture)
    }

    private var handleDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($drag) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let screen = UIScreen.main.bounds
                vm.toolbarPosition = CGPoint(
                    x: (vm.toolbarPosition.x + value.translation.width)
                        .clamped(to: 0...(screen.width  - 60)),
                    y: (vm.toolbarPosition.y + value.translation.height)
                        .clamped(to: 0...(screen.height - 60))
                )
            }
    }

    // MARK: - Reusable Button

    private func toolbarButton(
        systemImage: String,
        label:       String,
        isSelected:  Bool    = false,
        isAccent:    Bool    = false,
        action:      @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isAccent ? 20 : 18))
                .frame(width: 44, height: 44)
                .foregroundStyle(
                    isAccent || isSelected
                        ? themeManager.currentTheme.primary
                        : themeManager.currentTheme.textSecondary
                )
                .background(
                    isSelected
                        ? themeManager.currentTheme.primary.opacity(0.15)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .accessibilityLabel(label)
    }

    // MARK: - Dividers

    private var vDivider: some View {
        Divider().frame(width: 28).padding(.vertical, 2)
    }

    private var hDivider: some View {
        Divider().frame(height: 28).padding(.horizontal, 2)
    }
}

// MARK: - Comparable clamp
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
