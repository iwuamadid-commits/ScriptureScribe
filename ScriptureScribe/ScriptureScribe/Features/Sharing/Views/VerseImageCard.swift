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

    static let presets: [GradientPreset] = [
        GradientPreset(id: "warmSunset",   name: "Warm Sunset",
                       colors: [Color(red: 0.95, green: 0.55, blue: 0.25),
                                Color(red: 0.85, green: 0.30, blue: 0.45),
                                Color(red: 0.45, green: 0.20, blue: 0.55)],
                       startPoint: .topLeading, endPoint: .bottomTrailing),

        GradientPreset(id: "deepOcean",    name: "Deep Ocean",
                       colors: [Color(red: 0.06, green: 0.13, blue: 0.15),
                                Color(red: 0.12, green: 0.25, blue: 0.30),
                                Color(red: 0.17, green: 0.33, blue: 0.39)],
                       startPoint: .top, endPoint: .bottom),

        GradientPreset(id: "goldenHour",   name: "Golden Hour",
                       colors: [Color(red: 0.96, green: 0.82, blue: 0.55),
                                Color(red: 0.92, green: 0.65, blue: 0.40),
                                Color(red: 0.80, green: 0.45, blue: 0.30)],
                       startPoint: .top, endPoint: .bottom),

        GradientPreset(id: "midnightSky",  name: "Midnight Sky",
                       colors: [Color(red: 0.05, green: 0.05, blue: 0.15),
                                Color(red: 0.10, green: 0.10, blue: 0.30),
                                Color(red: 0.20, green: 0.15, blue: 0.40)],
                       startPoint: .topLeading, endPoint: .bottomTrailing),

        GradientPreset(id: "forestMist",   name: "Forest Mist",
                       colors: [Color(red: 0.15, green: 0.25, blue: 0.18),
                                Color(red: 0.22, green: 0.38, blue: 0.28),
                                Color(red: 0.35, green: 0.50, blue: 0.40)],
                       startPoint: .top, endPoint: .bottom),

        GradientPreset(id: "dustyRose",    name: "Dusty Rose",
                       colors: [Color(red: 0.55, green: 0.30, blue: 0.35),
                                Color(red: 0.70, green: 0.45, blue: 0.50),
                                Color(red: 0.85, green: 0.65, blue: 0.68)],
                       startPoint: .topLeading, endPoint: .bottomTrailing),

        GradientPreset(id: "softLavender", name: "Soft Lavender",
                       colors: [Color(red: 0.40, green: 0.30, blue: 0.60),
                                Color(red: 0.55, green: 0.45, blue: 0.72),
                                Color(red: 0.75, green: 0.65, blue: 0.85)],
                       startPoint: .top, endPoint: .bottom),

        GradientPreset(id: "earthyBrown",  name: "Earthy Brown",
                       colors: [Color(red: 0.35, green: 0.25, blue: 0.18),
                                Color(red: 0.50, green: 0.38, blue: 0.28),
                                Color(red: 0.65, green: 0.52, blue: 0.40)],
                       startPoint: .topLeading, endPoint: .bottomTrailing),

        GradientPreset(id: "royalBlue",    name: "Royal Blue",
                       colors: [Color(red: 0.08, green: 0.10, blue: 0.35),
                                Color(red: 0.15, green: 0.20, blue: 0.55),
                                Color(red: 0.25, green: 0.35, blue: 0.70)],
                       startPoint: .top, endPoint: .bottom),

        GradientPreset(id: "warmGray",     name: "Warm Gray",
                       colors: [Color(red: 0.35, green: 0.32, blue: 0.30),
                                Color(red: 0.50, green: 0.47, blue: 0.45),
                                Color(red: 0.65, green: 0.62, blue: 0.60)],
                       startPoint: .topLeading, endPoint: .bottomTrailing),
    ]
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

            // Watermark for free users — large centered "SS"
            if showWatermark {
                Text("SS")
                    .font(.system(size: 220, weight: .black, design: .serif))
                    .foregroundStyle(.white.opacity(0.15))
                    .rotationEffect(.degrees(-25))
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
