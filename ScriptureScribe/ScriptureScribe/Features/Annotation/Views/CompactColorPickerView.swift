//
//  CompactColorPickerView.swift
//  ScriptureScribe
//
//  Compact color picker for popover display (Noteful style).
//  Features a color wheel with hue ring + saturation/brightness square in center.
//

import SwiftUI

struct CompactColorPickerView: View {

    @Binding var selectedColor: UIColor

    @State private var hue:        Double = 0
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
            // Color wheel with saturation/brightness square
            ColorWheelView(hue: $hue, saturation: $saturation, brightness: $brightness)
                .frame(width: 240, height: 240)
                .padding(.top, 8)

            // Quick color presets
            HStack(spacing: 12) {
                ForEach(Array(presetColors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(Color(color))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .onTapGesture { selectPreset(color) }
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .onAppear { initHSB(from: selectedColor) }
        .onChange(of: hue)        { _, _ in selectedColor = currentUIColor }
        .onChange(of: saturation) { _, _ in selectedColor = currentUIColor }
        .onChange(of: brightness) { _, _ in selectedColor = currentUIColor }
    }

    private let presetColors: [UIColor] = [
        .black,
        UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1), // dark gray
        UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1), // red
        UIColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 1), // orange
        UIColor(red: 0.95, green: 0.9, blue: 0.3, alpha: 1), // yellow
        UIColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1), // green
        UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1), // blue
        UIColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1)  // purple
    ]

    private func initHSB(from color: UIColor) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue        = Double(h)
        saturation = Double(s)
        brightness = Double(b)
    }

    private func selectPreset(_ color: UIColor) {
        initHSB(from: color)
        selectedColor = color
    }
}

// MARK: - Color Wheel with Center Square

/// Color wheel: outer ring for hue, inner square for saturation/brightness
struct ColorWheelView: View {

    @Binding var hue:        Double
    @Binding var saturation: Double
    @Binding var brightness: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Outer hue ring
                HueRingView(hue: $hue, size: geo.size)

                // Inner saturation/brightness square
                let squareSize = geo.size.width * 0.62
                HSBSquareView(hue: $hue, saturation: $saturation, brightness: $brightness)
                    .frame(width: squareSize, height: squareSize)
            }
        }
    }
}

// MARK: - Hue Ring

/// Circular hue ring (rainbow)
struct HueRingView: View {

    @Binding var hue: Double
    let size: CGSize

    var body: some View {
        ZStack {
            // Rainbow gradient ring
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: rainbowColors),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    lineWidth: size.width * 0.15
                )

            // Selection indicator (white circle on the ring)
            let angle = hue * 360
            let radius = size.width / 2 - (size.width * 0.15) / 2
            let x = cos(angle * .pi / 180) * radius + size.width / 2
            let y = sin(angle * .pi / 180) * radius + size.height / 2

            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.3), radius: 2)
                .position(x: x, y: y)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let dx = value.location.x - center.x
                    let dy = value.location.y - center.y
                    var angle = atan2(dy, dx) * 180 / .pi
                    if angle < 0 { angle += 360 }
                    hue = angle / 360
                }
        )
    }

    private var rainbowColors: [Color] {
        stride(from: 0.0, through: 1.0, by: 1.0 / 30.0)
            .map { Color(hue: $0, saturation: 1, brightness: 1) }
    }
}

// MARK: - Saturation/Brightness Square

/// Center square: saturation (X) and brightness (Y)
struct HSBSquareView: View {

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
                    .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .position(x: x, y: y)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
