//
//  FontPickerBar.swift
//  ScriptureScribe
//
//  Horizontal scrolling font selector. Each font name is displayed
//  in its own typeface so users can preview the style at a glance.
//

import SwiftUI

struct FontPickerBar: View {

    @Binding var selectedFont: String

    /// (displayName, PostScript name for Font.custom)
    static let availableFonts: [(display: String, postScript: String)] = [
        ("Georgia",     "Georgia"),
        ("Avenir Next", "AvenirNext-Regular"),
        ("Didot",       "Didot"),
        ("Typewriter",  "AmericanTypewriter"),
        ("Copperplate", "Copperplate"),
        ("Palatino",    "Palatino-Roman"),
        ("Futura",      "Futura-Medium"),
        ("Baskerville", "Baskerville"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Self.availableFonts, id: \.postScript) { font in
                    let isSelected = selectedFont == font.postScript
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFont = font.postScript
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(font.display)
                                .font(.custom(font.postScript, size: 15))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                                .lineLimit(1)

                            // Selection indicator
                            Capsule()
                                .fill(isSelected ? Color.white : Color.clear)
                                .frame(height: 2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color.black.opacity(0.3))
    }
}
