//
//  VerseImageCard.swift
//  ScriptureScribe
//
//  The renderable verse card used both as the live preview in the composer
//  AND as the source for ImageRenderer. Must look identical in both contexts.
//

import SwiftUI

// MARK: - Background Model

enum VerseBackground: Hashable {
    case gradient(GradientPreset)
    case photo(UIImage)

    static var defaultBackground: VerseBackground {
        .gradient(.presets[0])
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .gradient(let preset): hasher.combine(preset.id)
        case .photo(let img):       hasher.combine(ObjectIdentifier(img))
        }
    }

    static func == (lhs: VerseBackground, rhs: VerseBackground) -> Bool {
        switch (lhs, rhs) {
        case (.gradient(let a), .gradient(let b)): return a.id == b.id
        case (.photo(let a), .photo(let b)):       return a === b
        default: return false
        }
    }
}

struct GradientPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let colors: [Color]
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    let isPremium: Bool

    /// All presets — free themes first, then premium.
    static let presets: [GradientPreset] = [
        // ── Free ──────────────────────────────────────────────────────────
        GradientPreset(id: "ivory",      name: "Ivory",
                       colors: [Color(red: 0.96, green: 0.93, blue: 0.87),
                                Color(red: 0.92, green: 0.88, blue: 0.80),
                                Color(red: 0.88, green: 0.84, blue: 0.76)],
                       startPoint: .top, endPoint: .bottom,
                       isPremium: false),

        GradientPreset(id: "forest",     name: "Forest",
                       colors: [Color(red: 0.15, green: 0.25, blue: 0.18),
                                Color(red: 0.22, green: 0.38, blue: 0.28),
                                Color(red: 0.35, green: 0.50, blue: 0.40)],
                       startPoint: .top, endPoint: .bottom,
                       isPremium: false),

        // ── Premium ───────────────────────────────────────────────────────
        GradientPreset(id: "parchment",  name: "Parchment",
                       colors: [Color(red: 0.87, green: 0.80, blue: 0.68),
                                Color(red: 0.80, green: 0.72, blue: 0.58),
                                Color(red: 0.72, green: 0.64, blue: 0.50)],
                       startPoint: .top, endPoint: .bottom,
                       isPremium: true),

        GradientPreset(id: "midnight",   name: "Midnight",
                       colors: [Color(red: 0.05, green: 0.05, blue: 0.15),
                                Color(red: 0.10, green: 0.10, blue: 0.30),
                                Color(red: 0.20, green: 0.15, blue: 0.40)],
                       startPoint: .topLeading, endPoint: .bottomTrailing,
                       isPremium: true),

        GradientPreset(id: "serene",     name: "Serene",
                       colors: [Color(red: 0.60, green: 0.78, blue: 0.82),
                                Color(red: 0.45, green: 0.65, blue: 0.72),
                                Color(red: 0.35, green: 0.55, blue: 0.65)],
                       startPoint: .top, endPoint: .bottom,
                       isPremium: true),

        GradientPreset(id: "blossom",    name: "Blossom",
                       colors: [Color(red: 0.90, green: 0.70, blue: 0.75),
                                Color(red: 0.82, green: 0.55, blue: 0.62),
                                Color(red: 0.72, green: 0.42, blue: 0.52)],
                       startPoint: .topLeading, endPoint: .bottomTrailing,
                       isPremium: true),

        GradientPreset(id: "slate",      name: "Slate",
                       colors: [Color(red: 0.35, green: 0.38, blue: 0.42),
                                Color(red: 0.48, green: 0.52, blue: 0.56),
                                Color(red: 0.62, green: 0.65, blue: 0.68)],
                       startPoint: .top, endPoint: .bottom,
                       isPremium: true),

        GradientPreset(id: "royal",      name: "Royal",
                       colors: [Color(red: 0.08, green: 0.10, blue: 0.35),
                                Color(red: 0.15, green: 0.20, blue: 0.55),
                                Color(red: 0.25, green: 0.35, blue: 0.70)],
                       startPoint: .top, endPoint: .bottom,
                       isPremium: true),
    ]

    /// Only the free presets.
    static let freePresets: [GradientPreset] = presets.filter { !$0.isPremium }

    /// Only the premium presets.
    static let premiumPresets: [GradientPreset] = presets.filter { $0.isPremium }
}

// MARK: - Verse Image Card

struct VerseImageCard: View {

    let verseText:      String
    let verseReference: String
    let background:     VerseBackground
    let fontName:       String
    let fontSize:       CGFloat
    let textAlignment:  TextAlignment
    let overlayOpacity: Double
    var showWatermark:  Bool = false

    var body: some View {
        ZStack {
            // Background
            backgroundLayer

            // Dark overlay for readability
            Color.black.opacity(overlayOpacity)

            // Verse content
            VStack(spacing: 20) {
                Spacer()

                Text(verseText.uppercased())
                    .font(.custom(fontName, size: fontSize))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(textAlignment)
                    .lineSpacing(fontSize * 0.25)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)

                Text(verseReference.uppercased())
                    .font(.custom(fontName, size: max(12, fontSize * 0.45)))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)

                Spacer()
            }
            .padding(36)

            // Watermark for free users — logo centered
            if showWatermark {
                Image("WatermarkLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .opacity(0.15)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch background {
        case .gradient(let preset):
            LinearGradient(
                colors:     preset.colors,
                startPoint: preset.startPoint,
                endPoint:   preset.endPoint
            )
        case .photo(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }
}
