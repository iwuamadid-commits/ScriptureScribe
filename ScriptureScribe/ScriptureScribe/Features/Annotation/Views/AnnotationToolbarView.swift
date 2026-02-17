//
//  AnnotationToolbarView.swift
//  ScriptureScribe
//
//  The floating toolbar that appears when annotation mode is active.
//  It lives on the right side of the screen by default, or the left side
//  if the user is left-handed (set in the toolbar's settings menu).
//
//  What's on the toolbar (top to bottom):
//    • Done button        — exits annotation mode and saves the drawing
//    • Tool buttons       — Pen, Highlighter, Eraser, Lasso
//    • Color swatch       — opens the color picker sheet
//    • Stroke size        — slider to make strokes thicker or thinner
//    • Guide lines toggle — turns ruled lines on/off
//    • Undo / Redo        — removes or restores the last stroke
//    • Settings menu      — left/right-handed, finger drawing toggle, guide spacing
//

import SwiftUI

struct AnnotationToolbarView: View {

    @ObservedObject var vm: AnnotationViewModel
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top) {
            if vm.isLeftHanded {
                toolbarPanel
                Spacer()
            } else {
                Spacer()
                toolbarPanel
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        // Color picker sheet
        .sheet(isPresented: $vm.showColorPicker) {
            ColorPickerWheelView(selectedColor: $vm.selectedColor)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Toolbar Panel

    private var toolbarPanel: some View {
        VStack(spacing: 4) {

            // — Done —
            toolbarButton(systemImage: "xmark.circle.fill", label: "Done", isAccent: true) {
                vm.toggleAnnotating()
            }

            divider

            // — Drawing Tools —
            ForEach(AnnotationViewModel.DrawingTool.allCases, id: \.self) { tool in
                toolbarButton(
                    systemImage: tool.systemImage,
                    label: tool.label,
                    isSelected: vm.selectedTool == tool
                ) {
                    vm.selectedTool = tool
                }
            }

            divider

            // — Color Swatch —
            Button {
                vm.showColorPicker = true
            } label: {
                Circle()
                    .fill(Color(vm.selectedColor))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.8), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("Choose color")

            // — Stroke Size Slider —
            VStack(spacing: 2) {
                // Preview dot shows the current stroke thickness
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

            divider

            // — Guide Lines Toggle —
            toolbarButton(
                systemImage: vm.showGuidelines ? "line.3.horizontal" : "line.horizontal.3",
                label: "Guidelines",
                isSelected: vm.showGuidelines
            ) {
                vm.showGuidelines.toggle()
            }

            // — Guide Spacing (only visible when guidelines are on) —
            if vm.showGuidelines {
                Menu {
                    ForEach(AnnotationViewModel.GuideSpacing.allCases, id: \.self) { spacing in
                        Button {
                            vm.guideSpacing = spacing
                        } label: {
                            Label(
                                spacing.rawValue,
                                systemImage: vm.guideSpacing == spacing ? "checkmark" : ""
                            )
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16))
                        .frame(width: 44, height: 36)
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
                .accessibilityLabel("Guide line spacing")
            }

            divider

            // — Undo —
            toolbarButton(systemImage: "arrow.uturn.backward", label: "Undo") {
                vm.undo()
            }

            // — Redo —
            toolbarButton(systemImage: "arrow.uturn.forward", label: "Redo") {
                vm.redo()
            }

            divider

            // — Settings Menu (left/right-handed + finger drawing) —
            Menu {
                Section("Handedness") {
                    Button {
                        vm.isLeftHanded = false
                    } label: {
                        Label("Right-Handed", systemImage: vm.isLeftHanded ? "" : "checkmark")
                    }
                    Button {
                        vm.isLeftHanded = true
                    } label: {
                        Label("Left-Handed", systemImage: vm.isLeftHanded ? "checkmark" : "")
                    }
                }

                Section("Input") {
                    Button {
                        vm.allowFingerDrawing.toggle()
                    } label: {
                        Label(
                            vm.allowFingerDrawing ? "Finger: On" : "Finger: Off",
                            systemImage: vm.allowFingerDrawing ? "hand.draw.fill" : "hand.draw"
                        )
                    }
                }

                Section("Canvas") {
                    Button(role: .destructive) {
                        vm.clearCanvas()
                    } label: {
                        Label("Clear Page", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
            .accessibilityLabel("More annotation options")
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    // MARK: - Reusable Sub-Views

    /// A simple icon button for the toolbar.
    private func toolbarButton(
        systemImage: String,
        label: String,
        isSelected: Bool = false,
        isAccent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isAccent ? 20 : 18))
                .frame(width: 44, height: 44)
                .foregroundStyle(
                    isAccent
                        ? themeManager.currentTheme.primary
                        : isSelected
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
        Divider()
            .frame(width: 28)
            .padding(.vertical, 2)
    }
}
