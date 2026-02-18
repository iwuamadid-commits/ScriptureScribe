//
//  AnnotationToolbarView.swift
//  ScriptureScribe
//
//  Floating side toolbar for the annotation engine. It is collapsible:
//    • Collapsed → shows a single pencil button to re-expand
//    • Expanded  → shows all tools, color, stroke, guide lines, undo/redo, settings
//
//  The toolbar docks on the right by default, or the left when left-handed mode is on.
//

import SwiftUI

struct AnnotationToolbarView: View {

    @ObservedObject var vm: AnnotationViewModel
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top) {
            if vm.isLeftHanded {
                content
                Spacer()
            } else {
                Spacer()
                content
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
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

    // A single round button — tap to re-open the full toolbar
    private var collapsedButton: some View {
        Button { vm.isToolbarCollapsed = false } label: {
            Image(systemName: "pencil.circle.fill")
                .font(.title)
                .foregroundStyle(themeManager.currentTheme.primary)
        }
        .frame(width: 44, height: 44)
        .background(.ultraThinMaterial, in: Circle())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        .accessibilityLabel("Expand toolbar")
    }

    // MARK: - Full Toolbar Panel

    private var expandedPanel: some View {
        VStack(spacing: 4) {

            // Collapse button
            toolbarButton(systemImage: "chevron.right", label: "Collapse", isAccent: true) {
                vm.isToolbarCollapsed = true
            }

            // Done
            toolbarButton(systemImage: "xmark.circle.fill", label: "Done", isAccent: true) {
                vm.toggleAnnotating()
            }

            divider

            // Drawing tools
            ForEach(AnnotationViewModel.DrawingTool.allCases, id: \.self) { tool in
                VStack(spacing: 0) {
                    toolbarButton(
                        systemImage: tool.systemImage,
                        label:       tool.label,
                        isSelected:  vm.selectedTool == tool
                    ) {
                        vm.selectedTool = tool
                    }
                    // Eraser type sub-picker (shown when eraser is selected)
                    if tool == .eraser && vm.selectedTool == .eraser {
                        eraserTypePicker
                    }
                }
            }

            divider

            // Color swatch
            Button { vm.showColorPicker = true } label: {
                Circle()
                    .fill(Color(vm.selectedColor))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("Choose color")

            // Stroke size slider (vertical)
            VStack(spacing: 2) {
                Circle()
                    .fill(Color(vm.selectedColor))
                    .frame(width: min(vm.strokeWidth * 2.5, 22), height: min(vm.strokeWidth * 2.5, 22))
                    .frame(width: 22, height: 22)
                Slider(value: $vm.strokeWidth, in: 1...12, step: 0.5)
                    .frame(width: 36)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 100)
                    .tint(Color(vm.selectedColor))
            }

            divider

            // Guide lines toggle
            toolbarButton(
                systemImage: vm.showGuidelines ? "line.3.horizontal" : "line.horizontal.3",
                label:       "Guidelines",
                isSelected:  vm.showGuidelines
            ) {
                vm.showGuidelines.toggle()
            }

            if vm.showGuidelines {
                Menu {
                    ForEach(AnnotationViewModel.GuideSpacing.allCases, id: \.self) { s in
                        Button {
                            vm.guideSpacing = s
                        } label: {
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

            divider

            // Undo / Redo
            toolbarButton(systemImage: "arrow.uturn.backward", label: "Undo") { vm.undo() }
            toolbarButton(systemImage: "arrow.uturn.forward",  label: "Redo") { vm.redo() }

            divider

            // Settings menu
            Menu {
                Section("Handedness") {
                    Button { vm.isLeftHanded = false } label: {
                        Label("Right-Handed", systemImage: vm.isLeftHanded ? "" : "checkmark")
                    }
                    Button { vm.isLeftHanded = true } label: {
                        Label("Left-Handed",  systemImage: vm.isLeftHanded ? "checkmark" : "")
                    }
                }
                Section("Input") {
                    Button { vm.allowFingerDrawing.toggle() } label: {
                        Label(
                            vm.allowFingerDrawing ? "Finger: On" : "Finger: Off",
                            systemImage: vm.allowFingerDrawing ? "hand.draw.fill" : "hand.draw"
                        )
                    }
                }
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
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    // MARK: - Eraser Type Sub-Picker

    private var eraserTypePicker: some View {
        VStack(spacing: 2) {
            ForEach(AnnotationViewModel.EraserType.allCases, id: \.self) { type in
                Button {
                    vm.eraserType = type
                } label: {
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
        }
        .padding(.bottom, 4)
    }

    // MARK: - Reusable Icon Button

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

    private var divider: some View {
        Divider().frame(width: 28).padding(.vertical, 2)
    }
}
