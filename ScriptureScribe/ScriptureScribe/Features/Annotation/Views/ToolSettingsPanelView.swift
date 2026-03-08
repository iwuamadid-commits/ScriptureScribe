//
//  ToolSettingsPanelView.swift
//  ScriptureScribe
//
//  Noteful-style dark settings sheet for pen, highlighter, and eraser.
//  Opens when the user taps the currently selected tool button a second time.
//
//  Pen panel:         stroke preview (style-aware) · style picker · size section
//  Highlighter panel: stroke preview · size section · straight-lines toggle
//  Eraser panel:      eraser type picker (Whole Line / Pixel) · size section
//
//  Size section layout:
//    ┌──────────────────────────────────────────┐
//    │  [ ] [ ] [ ] [ ] [ ]  ← 5 favorite slots │
//    │  ──────────────────── ← drag slider       │
//    └──────────────────────────────────────────┘
//  • Tap an EMPTY slot  → saves the current size into that slot
//  • Tap a FILLED slot  → instantly applies that saved size
//  • Long-press a slot  → clears it (back to empty)
//

import SwiftUI

struct ToolSettingsPanelView: View {

    @ObservedObject var vm: AnnotationViewModel
    let tool: AnnotationViewModel.DrawingTool

    /// Called when the user taps the color circle to switch to the full color picker.
    /// (Not used for the eraser, which has no color.)
    var onOpenColorPicker: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed helpers

    private var sliderRange: ClosedRange<CGFloat> {
        switch tool {
        case .pen:         return 1...20
        case .highlighter: return 4...80
        case .eraser:      return 3...60
        default:           return 1...20
        }
    }

    /// The size value that should be read/written for this tool.
    private var sizeBinding: Binding<CGFloat> {
        tool == .eraser
            ? Binding(get: { self.vm.eraserSize },   set: { self.vm.eraserSize   = $0 })
            : Binding(get: { self.vm.strokeWidth },  set: { self.vm.strokeWidth  = $0 })
    }

    private var currentToolSize: CGFloat {
        tool == .eraser ? vm.eraserSize : vm.strokeWidth
    }

    private var sheetHeight: CGFloat {
        switch tool {
        case .pen:         return 620
        case .highlighter: return 460
        case .eraser:      return 420
        default:           return 460
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.14).ignoresSafeArea()

            VStack(spacing: 0) {

                headerRow
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                // Eraser gets its own layout (no stroke preview, type picker instead)
                if tool == .eraser {
                    eraserTypeSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                } else {
                    strokePreview
                        .frame(height: 68)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    if tool == .pen {
                        penStylePicker
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }

                sizeSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                if tool == .highlighter || tool == .pen {
                    optionsSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }

                Spacer()
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .onDisappear {
            vm.saveCurrentToolSettings()
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 16) {
            Text(tool == .pen ? "Pen Tool"
                 : tool == .highlighter ? "Highlighter"
                 : "Eraser")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Spacer()

            // Color swatch — shown for pen and highlighter only
            if tool != .eraser {
                Button {
                    onOpenColorPicker?()
                    dismiss()
                } label: {
                    Circle()
                        .fill(Color(vm.selectedColor))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 2))
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
                .accessibilityLabel("Open color picker")
            }

            Button("Done") {
                vm.saveCurrentToolSettings()
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
        }
    }

    // MARK: - Eraser Type Picker

    private var eraserTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Mode")

            HStack(spacing: 10) {
                ForEach(AnnotationViewModel.EraserType.allCases, id: \.self) { type in
                    let isSelected = vm.eraserType == type
                    Button {
                        vm.eraserType = type
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: type == .wholeLine ? "line.diagonal" : "circle.dotted")
                                .font(.body)
                            Text(type == .wholeLine ? "Whole Line" : "Pixel")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(isSelected ? .white : Color(white: 0.65))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(isSelected ? Color(white: 0.30) : Color(white: 0.20))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.white.opacity(0.5) : Color.clear,
                                        lineWidth: 1.5)
                        )
                    }
                }
            }

            // Pixel size note
            if vm.eraserType == .wholeLine {
                Text("Erases the entire stroke you touch.")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.45))
                    .padding(.top, 2)
            } else {
                Text("Erases only where you drag. Size controls how wide.")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.45))
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Stroke Preview

    private var strokePreview: some View {
        Canvas { ctx, size in
            let midY = size.height / 2

            if tool == .highlighter {
                let band = min(vm.strokeWidth, size.height - 8)
                var path = Path()
                path.move(to: CGPoint(x: 16, y: midY))
                path.addLine(to: CGPoint(x: size.width - 16, y: midY))
                ctx.stroke(path,
                           with: .color(Color(vm.selectedColor).opacity(0.45)),
                           style: StrokeStyle(lineWidth: band, lineCap: .butt))
            } else {
                let lineColor: Color
                let lineWidth: CGFloat
                let lineCap: CGLineCap

                switch vm.penStyle {
                case .fountain:
                    lineColor = Color(vm.selectedColor)
                    lineWidth = min(vm.strokeWidth, size.height * 0.65)
                    lineCap   = .round
                case .calligraphy:
                    lineColor = Color(vm.selectedColor)
                    lineWidth = min(vm.strokeWidth, size.height * 0.65)
                    lineCap   = .round
                case .crayon:
                    lineColor = Color(vm.selectedColor).opacity(0.75)
                    lineWidth = min(vm.strokeWidth * 1.8, size.height - 8)
                    lineCap   = .round
                }

                let bump = max(lineWidth * 0.7, 2.5)
                var path = Path()
                switch vm.penStyle {
                case .calligraphy:
                    // Smooth elegant curve
                    path.move(to: CGPoint(x: 16, y: midY + 4))
                    path.addCurve(
                        to: CGPoint(x: size.width - 16, y: midY - 4),
                        control1: CGPoint(x: size.width * 0.3, y: midY - bump * 1.2),
                        control2: CGPoint(x: size.width * 0.7, y: midY + bump * 1.2)
                    )
                case .crayon:
                    // Bold zigzag
                    path.move(to: CGPoint(x: 16, y: midY))
                    path.addLine(to: CGPoint(x: size.width * 0.2, y: midY - bump * 0.6))
                    path.addLine(to: CGPoint(x: size.width * 0.4, y: midY + bump * 0.6))
                    path.addLine(to: CGPoint(x: size.width * 0.6, y: midY - bump * 0.6))
                    path.addLine(to: CGPoint(x: size.width * 0.8, y: midY + bump * 0.6))
                    path.addLine(to: CGPoint(x: size.width - 16,  y: midY))
                default:
                    // Fountain — smooth zigzag
                    path.move(to: CGPoint(x: 16, y: midY))
                    path.addLine(to: CGPoint(x: size.width * 0.17, y: midY - bump))
                    path.addLine(to: CGPoint(x: size.width * 0.32, y: midY + bump))
                    path.addLine(to: CGPoint(x: size.width * 0.48, y: midY - bump))
                    path.addLine(to: CGPoint(x: size.width * 0.63, y: midY + bump))
                    path.addLine(to: CGPoint(x: size.width * 0.78, y: midY - bump))
                    path.addLine(to: CGPoint(x: size.width - 16,   y: midY))
                }
                ctx.stroke(path,
                           with: .color(lineColor),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap,
                                             lineJoin: .round))
            }
        }
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Pen Style Picker

    private var penStylePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Style")

            HStack(spacing: 12) {
                ForEach(AnnotationViewModel.PenStyle.allCases, id: \.self) { style in
                    styleButton(for: style)
                }
                Spacer()
            }
        }
    }

    private func styleButton(for style: AnnotationViewModel.PenStyle) -> some View {
        let isSelected = vm.penStyle == style
        return Button {
            vm.penStyle = style
        } label: {
            VStack(spacing: 8) {
                Canvas { ctx, size in
                    let mid = size.height / 2
                    var path = Path()
                    switch style {
                    case .fountain:
                        // Smooth curve
                        path.move(to: CGPoint(x: 4, y: mid + 3))
                        path.addCurve(
                            to: CGPoint(x: size.width - 4, y: mid - 3),
                            control1: CGPoint(x: size.width * 0.3, y: mid - 7),
                            control2: CGPoint(x: size.width * 0.7, y: mid + 5)
                        )
                        ctx.stroke(path, with: .color(Color(white: 0.90)),
                                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    case .calligraphy:
                        // Thick-to-thin elegant stroke
                        let thinW: CGFloat = 1.0
                        let thickW: CGFloat = 5.0
                        var p1 = Path()
                        p1.move(to: CGPoint(x: 4, y: mid - 6))
                        p1.addLine(to: CGPoint(x: size.width * 0.45, y: mid + 6))
                        ctx.stroke(p1, with: .color(Color(white: 0.90)),
                                   style: StrokeStyle(lineWidth: thickW, lineCap: .round))
                        var p2 = Path()
                        p2.move(to: CGPoint(x: size.width * 0.45, y: mid + 6))
                        p2.addCurve(
                            to: CGPoint(x: size.width - 4, y: mid - 4),
                            control1: CGPoint(x: size.width * 0.6, y: mid + 2),
                            control2: CGPoint(x: size.width * 0.8, y: mid - 6)
                        )
                        ctx.stroke(p2, with: .color(Color(white: 0.90)),
                                   style: StrokeStyle(lineWidth: thinW, lineCap: .round))
                    case .crayon:
                        // Bold waxy stroke
                        path.move(to: CGPoint(x: 4, y: mid + 2))
                        path.addLine(to: CGPoint(x: size.width * 0.35, y: mid - 3))
                        path.addLine(to: CGPoint(x: size.width * 0.65, y: mid + 3))
                        path.addLine(to: CGPoint(x: size.width - 4, y: mid - 1))
                        ctx.stroke(path, with: .color(Color(white: 0.80)),
                                   style: StrokeStyle(lineWidth: 5, lineCap: .round,
                                                      lineJoin: .round))
                    }
                }
                .frame(width: 56, height: 28)

                Text(style.label)
                    .font(.caption2)
                    .foregroundStyle(Color(white: isSelected ? 1.0 : 0.60))
            }
            .frame(width: 84, height: 74)
            .background(isSelected ? Color(white: 0.28) : Color(white: 0.20))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.white.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
        }
    }

    // MARK: - Size Section

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // For the eraser in whole-line mode, note that size only applies to pixel mode
            if tool == .eraser && vm.eraserType == .wholeLine {
                sectionLabel("Size  ·  applies in Pixel mode")
            } else {
                sectionLabel("Size")
            }

            favoritesRow
                .opacity(tool == .eraser && vm.eraserType == .wholeLine ? 0.45 : 1.0)

            Slider(value: sizeBinding, in: sliderRange,
                   step: tool == .pen ? 0.5 : 1)
                .tint(tool == .eraser ? Color(white: 0.60) : Color(vm.selectedColor))
                .opacity(tool == .eraser && vm.eraserType == .wholeLine ? 0.45 : 1.0)
        }
    }

    // MARK: - Favorites Row

    private var favoritesRow: some View {
        let favorites: [Double?] = {
            switch tool {
            case .pen:         return vm.penFavoriteSizes
            case .highlighter: return vm.highlighterFavoriteSizes
            case .eraser:      return vm.eraserFavoriteSizes
            default:           return vm.penFavoriteSizes
            }
        }()

        return HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { idx in
                favSlotButton(index: idx, storedSize: favorites[idx].map { CGFloat($0) })
            }
        }
    }

    private func favSlotButton(index: Int, storedSize: CGFloat?) -> some View {
        let isActive = storedSize.map { abs(currentToolSize - $0) < 0.5 } ?? false

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color(white: 0.32) : Color(white: 0.20))

            if let size = storedSize {
                Circle()
                    .fill(Color.white.opacity(isActive ? 1.0 : 0.72))
                    .frame(width: dotDiameter(for: size), height: dotDiameter(for: size))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(white: 0.38),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Color(white: 0.42))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            if let size = storedSize {
                sizeBinding.wrappedValue = size
            } else {
                vm.setFavoriteSize(currentToolSize, at: index, for: tool)
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if storedSize != nil {
                vm.clearFavoriteSize(at: index, for: tool)
            }
        }
    }

    /// Dot diameter scaled proportionally to the current tool's slider range.
    private func dotDiameter(for size: CGFloat) -> CGFloat {
        let minDot: CGFloat = 4
        let maxDot: CGFloat = 28
        let lo = sliderRange.lowerBound
        let hi = sliderRange.upperBound
        let t  = max(0, min(1, (size - lo) / (hi - lo)))
        return minDot + t * (maxDot - minDot)
    }

    // MARK: - Options Section (Highlighter only)

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Options")

            Toggle(isOn: $vm.highlighterStraightLines) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool == .pen ? "Auto Shapes" : "Draw Straight Lines")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Text(tool == .pen
                         ? "Draw, then hold still at the end to snap to a line, circle, or rectangle."
                         : "Every stroke snaps to a straight line.")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.55))
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .green))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(white: 0.20))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(white: 0.55))
            .textCase(.uppercase)
            .tracking(1)
    }
}
