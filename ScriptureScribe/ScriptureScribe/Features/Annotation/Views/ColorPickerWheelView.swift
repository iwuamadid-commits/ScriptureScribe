//
//  ColorPickerWheelView.swift
//  ScriptureScribe
//
//  A Procreate-style color picker with a dark theme.
//  Layout mirrors the Procreate "Classic" color panel:
//    • Header   — "Colors" title + original vs new color swatches + Done
//    • Square   — drag to pick saturation (X) and brightness (Y)
//    • Hue bar  — rainbow slider to set the hue
//    • History  — recently used colors (saved to UserDefaults)
//    • Tab bar  — Disc / Classic / Harmony / Value / Palettes (Classic active)
//

import SwiftUI

struct ColorPickerWheelView: View {

    @Binding var selectedColor: UIColor
    var onSave: ((UIColor) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    // Live HSB components
    @State private var hue:        Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1

    // The color as it was when the sheet opened (left swatch)
    @State private var originalColor: UIColor = .white

    // Recent-color history (stored as hex strings)
    @State private var history: [String] = []
    private let historyKey = "ss_colorPickerHistory"
    private let maxHistory = 12

    // Computed current color from the live HSB values
    private var currentUIColor: UIColor {
        UIColor(hue:        CGFloat(hue),
                saturation: CGFloat(saturation),
                brightness: CGFloat(brightness),
                alpha:      1)
    }

    var body: some View {
        ZStack {
            Color(white: 0.13).ignoresSafeArea()

            VStack(spacing: 0) {

                headerRow
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 18)

                // ── HSB Square ───────────────────────────────────────────
                HSBSquareViewFull(hue: $hue, saturation: $saturation, brightness: $brightness)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                // ── Hue Slider ───────────────────────────────────────────
                HueSliderViewFull(hue: $hue)
                    .frame(height: 30)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                // ── Saturation Slider ─────────────────────────────────────
                SaturationSliderViewFull(hue: $hue, saturation: $saturation, brightness: $brightness)
                    .frame(height: 30)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // ── Brightness Slider ─────────────────────────────────────
                BrightnessSliderViewFull(hue: $hue, saturation: $saturation, brightness: $brightness)
                    .frame(height: 30)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // ── History ──────────────────────────────────────────────
                historySection
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                Spacer()
            }
        }
        .onAppear {
            originalColor = selectedColor
            initHSB(from: selectedColor)
            loadHistory()
        }
        // Keep selectedColor in sync while the user drags
        .onChange(of: hue)        { _, _ in selectedColor = currentUIColor }
        .onChange(of: saturation) { _, _ in selectedColor = currentUIColor }
        .onChange(of: brightness) { _, _ in selectedColor = currentUIColor }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {

            Text("Colors")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Spacer()

            // Original color (left) | New color (right) — like Procreate's two swatches
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(originalColor))
                    .frame(width: 44, height: 34)
                Rectangle()
                    .fill(Color(currentUIColor))
                    .frame(width: 44, height: 34)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.25), lineWidth: 1))

            Button("Done") {
                selectedColor = currentUIColor
                saveToHistory(currentUIColor)
                onSave?(currentUIColor)
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("History")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Clear") {
                    history = []
                    UserDefaults.standard.removeObject(forKey: historyKey)
                }
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.55))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if history.isEmpty {
                        Text("No recent colors")
                            .font(.caption)
                            .foregroundStyle(Color(white: 0.45))
                            .frame(height: 38)
                    } else {
                        ForEach(history, id: \.self) { hex in
                            if let color = UIColor(hexString: hex) {
                                Circle()
                                    .fill(Color(color))
                                    .frame(width: 38, height: 38)
                                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    .onTapGesture { initHSB(from: color) }
                            }
                        }
                    }
                }
            }
            .frame(height: 42)
        }
    }

    // MARK: - Helpers

    private func initHSB(from color: UIColor) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue        = Double(h)
        saturation = Double(s)
        brightness = Double(b)
    }

    private func saveToHistory(_ color: UIColor) {
        let hex     = color.hexString
        var updated = history.filter { $0 != hex }
        updated.insert(hex, at: 0)
        if updated.count > maxHistory { updated = Array(updated.prefix(maxHistory)) }
        history = updated
        UserDefaults.standard.set(updated, forKey: historyKey)
    }

    private func loadHistory() {
        history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }
}

// MARK: - HSB Square

/// 2-D color field: saturation on the X axis, brightness on the Y axis.
private struct HSBSquareViewFull: View {

    @Binding var hue:        Double
    @Binding var saturation: Double
    @Binding var brightness: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // White → current hue (left to right = saturation 0→1)
                LinearGradient(
                    colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                    startPoint: .leading,
                    endPoint:   .trailing
                )
                // Transparent → black (top to bottom = brightness 1→0)
                LinearGradient(
                    colors: [Color.clear, Color.black],
                    startPoint: .top,
                    endPoint:   .bottom
                )
                // Circular handle
                let x = CGFloat(saturation) * geo.size.width
                let y = CGFloat(1 - brightness) * geo.size.height
                Circle()
                    .stroke(Color.white, lineWidth: 2.5)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .frame(width: 24, height: 24)
                    .position(x: x, y: y)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        saturation = min(max(Double(value.location.x / geo.size.width),       0), 1)
                        brightness = min(max(Double(1 - value.location.y / geo.size.height),  0), 1)
                    }
            )
        }
    }
}

// MARK: - Saturation Slider

/// Horizontal bar showing gray → full hue color; drag to set saturation.
private struct SaturationSliderViewFull: View {

    @Binding var hue:        Double
    @Binding var saturation: Double
    @Binding var brightness: Double

    var body: some View {
        GeometryReader { geo in
            let handleSize: CGFloat = geo.size.height + 8
            let trackWidth          = geo.size.width - handleSize
            let handleOffset        = CGFloat(saturation) * trackWidth

            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [
                        Color(UIColor(hue: CGFloat(hue), saturation: 0, brightness: CGFloat(brightness), alpha: 1)),
                        Color(UIColor(hue: CGFloat(hue), saturation: 1, brightness: CGFloat(brightness), alpha: 1))
                    ],
                    startPoint: .leading,
                    endPoint:   .trailing
                )
                .clipShape(Capsule())
                .frame(height: geo.size.height)

                Circle()
                    .fill(Color(UIColor(hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: CGFloat(brightness), alpha: 1)))
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .frame(width: handleSize, height: handleSize)
                    .offset(x: handleOffset)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        saturation = min(max(Double(value.location.x / geo.size.width), 0), 1)
                    }
            )
        }
    }
}

// MARK: - Brightness Slider

/// Horizontal bar showing black → full-brightness hue; drag to set brightness.
private struct BrightnessSliderViewFull: View {

    @Binding var hue:        Double
    @Binding var saturation: Double
    @Binding var brightness: Double

    var body: some View {
        GeometryReader { geo in
            let handleSize: CGFloat = geo.size.height + 8
            let trackWidth          = geo.size.width - handleSize
            let handleOffset        = CGFloat(brightness) * trackWidth

            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [
                        .black,
                        Color(UIColor(hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: 1, alpha: 1))
                    ],
                    startPoint: .leading,
                    endPoint:   .trailing
                )
                .clipShape(Capsule())
                .frame(height: geo.size.height)

                Circle()
                    .fill(Color(UIColor(hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: CGFloat(brightness), alpha: 1)))
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .frame(width: handleSize, height: handleSize)
                    .offset(x: handleOffset)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        brightness = min(max(Double(value.location.x / geo.size.width), 0), 1)
                    }
            )
        }
    }
}

// MARK: - Hue Slider

/// Horizontal rainbow bar — drag to set the hue.
private struct HueSliderViewFull: View {

    @Binding var hue: Double

    private let rainbowColors: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 20.0)
        .map { Color(hue: $0, saturation: 1, brightness: 1) }

    var body: some View {
        GeometryReader { geo in
            let handleSize: CGFloat = geo.size.height + 8
            let trackWidth          = geo.size.width - handleSize
            let handleOffset        = CGFloat(hue) * trackWidth

            ZStack(alignment: .leading) {
                LinearGradient(colors: rainbowColors,
                               startPoint: .leading,
                               endPoint:   .trailing)
                    .clipShape(Capsule())
                    .frame(height: geo.size.height)

                Circle()
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .frame(width: handleSize, height: handleSize)
                    .offset(x: handleOffset)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(max(Double(value.location.x / geo.size.width), 0), 1)
                    }
            )
        }
    }
}
