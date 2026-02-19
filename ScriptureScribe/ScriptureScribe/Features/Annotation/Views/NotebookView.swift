//
//  NotebookView.swift
//  ScriptureScribe
//
//  The notebook panel shown on the right side when split-view mode is active.
//  It's a blank drawing surface with built-in guide lines — like a ruled notepad
//  next to the Bible text. The user can write freely with Apple Pencil or finger.
//  Drawings are saved per chapter (keyed as "notebook_GEN.1" etc).
//

import SwiftUI
import PencilKit

struct NotebookView: View {

    @ObservedObject var vm: AnnotationViewModel
    let chapterId: String        // the current Bible chapter, used to key notebook saves

    @EnvironmentObject var themeManager: ThemeManager

    private var notebookChapterId: String { "notebook_\(chapterId)" }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Notebook background
                themeManager.currentTheme.surface
                    .ignoresSafeArea()

                // Guide lines (always on in notebook mode)
                Canvas { context, size in
                    let lineColor = themeManager.currentTheme.border.opacity(0.5)
                    var path = Path()
                    var y = vm.guideSpacing.lineInterval
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += vm.guideSpacing.lineInterval
                    }
                    context.stroke(path, with: .color(lineColor), lineWidth: 0.75)
                }
                .allowsHitTesting(false)

                // Drawing canvas — use actual view dimensions instead of UIScreen.main
                AnnotationCanvasView(
                    vm:             vm,
                    chapterId:      notebookChapterId,
                    contentHeight:  geo.size.height,
                    containerWidth: geo.size.width
                )
                .allowsHitTesting(true)
            }
        }
        .overlay(alignment: .top) {
            // Spacing picker at the top of the notebook
            HStack(spacing: 8) {
                Text("Lines:")
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                ForEach(AnnotationViewModel.GuideSpacing.allCases, id: \.self) { spacing in
                    Button {
                        vm.guideSpacing = spacing
                    } label: {
                        Text(spacing.rawValue)
                            .font(.caption.weight(vm.guideSpacing == spacing ? .bold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                vm.guideSpacing == spacing
                                    ? themeManager.currentTheme.primary.opacity(0.15)
                                    : Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(
                                vm.guideSpacing == spacing
                                    ? themeManager.currentTheme.primary
                                    : themeManager.currentTheme.textSecondary
                            )
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }
    }
}
