//
//  SizePresetViews.swift
//  ScriptureScribe
//
//  Shared pieces for the five saved sizes (pen, highlighter, eraser):
//    • SizeDot           — a dot scaled to a size within the tool's range
//    • SizeAdjuster      — "Adjusting size 3 · 2.5" label + slider for the picked slot
//    • SizePopoverView   — the toolbar's size popup (optionally with the five slots)
//
//  The picked slot always matches the size the tool is drawing with. Tapping a slot
//  picks it; the slider changes the picked slot and saves it automatically.
//

import SwiftUI

// MARK: - Size Dot

struct SizeDot: View {
    let size:        Double
    let range:       ClosedRange<CGFloat>
    let minDiameter: CGFloat
    let maxDiameter: CGFloat
    let color:       Color

    var body: some View {
        let t = max(0, min(1, (CGFloat(size) - range.lowerBound) / (range.upperBound - range.lowerBound)))
        Circle()
            .fill(color)
            .frame(width:  minDiameter + t * (maxDiameter - minDiameter),
                   height: minDiameter + t * (maxDiameter - minDiameter))
    }
}

// MARK: - Size Formatting

enum SizeFormat {
    /// "3" or "2.5": whole numbers drop the decimal.
    static func string(_ size: Double) -> String {
        size.rounded() == size ? String(Int(size)) : String(format: "%.1f", size)
    }
}

// MARK: - Size Adjuster (label + slider)

struct SizeAdjuster: View {
    @ObservedObject var vm: AnnotationViewModel
    let tool:           AnnotationViewModel.DrawingTool
    let labelColor:     Color
    let valueColor:     Color
    let tint:           Color

    var body: some View {
        let index = vm.selectedSizeSlot(for: tool)
        let sizes = vm.favoriteSizes(for: tool)
        let size  = sizes.indices.contains(index) ? sizes[index] : 0

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Adjusting size \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(labelColor)
                Spacer()
                Text(SizeFormat.string(size))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(valueColor)
            }
            Slider(
                value: Binding(
                    get: { CGFloat(size) },
                    set: { vm.adjustSelectedSize(to: $0, for: tool) }
                ),
                in:   AnnotationViewModel.sizeRange(for: tool),
                step: AnnotationViewModel.sizeStep(for: tool)
            )
            .tint(tint)
            .accessibilityLabel("Size \(index + 1)")
            .accessibilityValue(SizeFormat.string(size))
        }
    }
}

// MARK: - Toolbar Size Popover

/// The size popup opened from the toolbar. With `showsSlots`, it also shows the five
/// sizes (used where the toolbar shows a single size button instead of five dots).
struct SizePopoverView: View {
    @ObservedObject var vm: AnnotationViewModel
    let tool:       AnnotationViewModel.DrawingTool
    let showsSlots: Bool
    let theme:      any AppTheme

    var body: some View {
        let sizes    = vm.favoriteSizes(for: tool)
        let selected = vm.selectedSizeSlot(for: tool)
        let range    = AnnotationViewModel.sizeRange(for: tool)

        VStack(alignment: .leading, spacing: 14) {
            if showsSlots {
                HStack(spacing: 8) {
                    ForEach(sizes.indices, id: \.self) { idx in
                        let isSelected = idx == selected
                        Button {
                            vm.selectSizeSlot(idx, for: tool)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isSelected ? theme.primary.opacity(0.14) : theme.border.opacity(0.35))
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? theme.primary : Color.clear, lineWidth: 2)
                                SizeDot(size: sizes[idx], range: range,
                                        minDiameter: 4, maxDiameter: 24,
                                        color: theme.text.opacity(isSelected ? 1 : 0.7))
                            }
                            .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Size \(idx + 1), \(SizeFormat.string(sizes[idx]))")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }

            SizeAdjuster(
                vm:         vm,
                tool:       tool,
                labelColor: theme.textSecondary,
                valueColor: theme.text,
                tint:       theme.primary
            )
        }
        .padding(16)
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(theme.surface)
    }
}
