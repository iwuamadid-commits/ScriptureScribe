//
//  AppTheme.swift
//  ScriptureScribe
//
//  Defines the AppTheme protocol and all 8 themes.
//  ThemeManager persists the user's choice and injects the active theme as an environment object.
//

import Combine
import SwiftUI

// MARK: - Protocol

protocol AppTheme {
    var name: String { get }
    var background: Color { get }   // main screen background
    var surface: Color { get }      // cards, sheets, sidebars
    var primary: Color { get }      // buttons, active tab, links
    var accent: Color { get }       // highlights, badges, streaks
    var text: Color { get }         // primary body text
    var textSecondary: Color { get } // captions, placeholders
    var border: Color { get }       // dividers, input borders
}

// MARK: - 8 Themes

struct IvoryTheme: AppTheme {
    let name = "Ivory"
    let background    = Color(hex: "#FAFAF8")
    let surface       = Color(hex: "#FFFFFF")
    let primary       = Color(hex: "#5C8A6B") // sage green
    let accent        = Color(hex: "#4A7A5A")
    let text          = Color(hex: "#1A1A1A")
    let textSecondary = Color(hex: "#6B6B6B")
    let border        = Color(hex: "#E5E5E3")
}

struct ParchmentTheme: AppTheme {
    let name = "Parchment"
    let background    = Color(hex: "#F4ECD8")
    let surface       = Color(hex: "#FAF3E3")
    let primary       = Color(hex: "#3D2B1F") // dark ink
    let accent        = Color(hex: "#6B4A2A")
    let text          = Color(hex: "#2C1A0E")
    let textSecondary = Color(hex: "#7A5C3E")
    let border        = Color(hex: "#D4C4A0")
}

struct MidnightTheme: AppTheme {
    let name = "Midnight"
    let background    = Color(hex: "#0D1B2A") // deep navy
    let surface       = Color(hex: "#1A2D42")
    let primary       = Color(hex: "#D4A843") // gold
    let accent        = Color(hex: "#F0C060")
    let text          = Color(hex: "#E8E8E8")
    let textSecondary = Color(hex: "#9AABB8")
    let border        = Color(hex: "#2A3D52")
}

struct SereneTheme: AppTheme {
    let name = "Serene"
    let background    = Color(hex: "#F5F0FF") // soft lavender
    let surface       = Color(hex: "#FFFFFF")
    let primary       = Color(hex: "#8B7EC8")
    let accent        = Color(hex: "#7B6DB8")
    let text          = Color(hex: "#2D2540")
    let textSecondary = Color(hex: "#8B80A8")
    let border        = Color(hex: "#DDD8EE")
}

struct ForestTheme: AppTheme {
    let name = "Forest"
    let background    = Color(hex: "#1A2E1A") // deep green
    let surface       = Color(hex: "#243824")
    let primary       = Color(hex: "#C8A96B") // warm tan
    let accent        = Color(hex: "#D4B87A")
    let text          = Color(hex: "#E8E0D0")
    let textSecondary = Color(hex: "#A0A888")
    let border        = Color(hex: "#2E4A2E")
}

struct SunriseTheme: AppTheme {
    let name = "Sunrise"
    let background    = Color(hex: "#FFF8F0")
    let surface       = Color(hex: "#FFFFFF")
    let primary       = Color(hex: "#E87040") // warm orange
    let accent        = Color(hex: "#F08850")
    let text          = Color(hex: "#2A1A10")
    let textSecondary = Color(hex: "#9A6A50")
    let border        = Color(hex: "#F0D8C8")
}

struct SlateTheme: AppTheme {
    let name = "Slate"
    let background    = Color(hex: "#F0F4F8")
    let surface       = Color(hex: "#FFFFFF")
    let primary       = Color(hex: "#5B7FA6") // cool grey-blue
    let accent        = Color(hex: "#4A6E95")
    let text          = Color(hex: "#1A2A3A")
    let textSecondary = Color(hex: "#6A7A8A")
    let border        = Color(hex: "#D8E4EE")
}

struct RoyalTheme: AppTheme {
    let name = "Royal"
    let background    = Color(hex: "#1A0A14") // deep burgundy
    let surface       = Color(hex: "#2A1420")
    let primary       = Color(hex: "#D4A843") // gold
    let accent        = Color(hex: "#F0C060")
    let text          = Color(hex: "#F0E8E0")
    let textSecondary = Color(hex: "#C0A090")
    let border        = Color(hex: "#3A1A28")
}

// MARK: - ThemeManager

final class ThemeManager: ObservableObject {

    static let allThemes: [any AppTheme] = [
        IvoryTheme(), ParchmentTheme(), MidnightTheme(), SereneTheme(),
        ForestTheme(), SunriseTheme(), SlateTheme(), RoyalTheme()
    ]

    @AppStorage("selectedTheme") private var selectedThemeName: String = "Ivory"
    @Published var currentTheme: any AppTheme = IvoryTheme()

    init() {
        currentTheme = theme(named: selectedThemeName)
    }

    func setTheme(_ theme: any AppTheme) {
        selectedThemeName = theme.name
        currentTheme = theme
    }

    private func theme(named name: String) -> any AppTheme {
        ThemeManager.allThemes.first { $0.name == name } ?? IvoryTheme()
    }
}
