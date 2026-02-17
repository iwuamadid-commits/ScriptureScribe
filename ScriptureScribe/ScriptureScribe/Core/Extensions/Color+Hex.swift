//
//  Color+Hex.swift
//  ScriptureScribe
//

import SwiftUI

// MARK: - UIColor Hex Helpers (used by the annotation color picker)

extension UIColor {

    /// Returns a 6-character uppercase hex string for this color (e.g. "5C8A6B").
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }

    /// Creates a UIColor from a 6-character hex string (with or without "#").
    /// Returns nil if the string is not a valid hex color.
    convenience init?(hexString: String) {
        let clean = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6 else { return nil }
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        self.init(
            red:   CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >>  8) & 0xFF) / 255,
            blue:  CGFloat( int        & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - SwiftUI Color from Hex

extension Color {
    /// Initialize a Color from a hex string (e.g. "#5C8A6B" or "5C8A6B").
    /// Supports 3-digit (RGB), 6-digit (RGB), and 8-digit (ARGB) hex values.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
