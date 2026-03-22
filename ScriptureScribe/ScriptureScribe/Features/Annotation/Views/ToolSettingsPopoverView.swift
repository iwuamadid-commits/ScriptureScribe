//
//  ToolSettingsPopoverView.swift
//  ScriptureScribe
//
//  Compact popover showing color picker + stroke slider for active tool.
//  Appears when the user taps the currently selected tool button.
//

import SwiftUI

struct ToolSettingsPopoverView: View {

    @Binding var color: UIColor
    @Binding var strokeWidth: CGFloat
    let tool: AnnotationViewModel.DrawingTool
    let onSaveColor: (UIColor) -> Void

    @EnvironmentObject var themeManager: ThemeManager

    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1

    private var currentUIColor: UIColor {
        UIColor(hue:        CGFloat(hue),
                saturation: CGFloat(saturation),
                brightness: CGFloat(brightness),
                alpha:      1)
    }

    var body: some View {
        VStack(spacing: 16) {

            // ── Color Square + Hue Slider ───────────────────────────────
            HSBSquareViewFull(hue: $hue, saturation: $saturation, brightness: $brightness)
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 8)

            HueSliderViewFull(hue: $hue)
                .frame(height: 24)
                .padding(.horizontal, 12)

            // ── Stroke Width Slider ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Stroke Width")
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)

                HStack(spacing: 12) {
                    // Preview circle showing current color + width
                    Circle()
                        .fill(Color(color))
                        .frame(width: min(strokeWidth * 2, 24),
                               height: min(strokeWidth * 2, 24))

                    Slider(value: $strokeWidth, in: 1...12, step: 0.5)
                        .tint(Color(color))
                }
            }
            .padding(.horizontal, 12)

            // ── Save Color Button ────────────────────────────────────────
            Button {
                onSaveColor(color)
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Save Color")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(themeManager.currentTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 240)
        .onAppear { initHSB(from: color) }
        .onChange(of: hue)        { _, _ in color = currentUIColor }
        .onChange(of: saturation) { _, _ in color = currentUIColor }
        .onChange(of: brightness) { _, _ in color = currentUIColor }
    }

    private func initHSB(from color: UIColor) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue        = Double(h)
        saturation = Double(s)
        brightness = Double(b)
    }
}
