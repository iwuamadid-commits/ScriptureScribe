//
//  GuideLineOverlayView.swift
//  ScriptureScribe
//
//  Draws faint horizontal lines across the reading area — like lined paper —
//  to help keep handwriting straight and even.
//
//  Three spacing options (Narrow / Medium / Wide) let the user match the lines
//  to their natural handwriting size.
//
//  The lines are always in sync with the active theme's border color so they
//  look good on every background.
//

import SwiftUI

struct GuideLineOverlayView: View {

    let spacing: AnnotationViewModel.GuideSpacing

    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        // Canvas draws the guide lines using low-level 2D drawing commands.
        // This is faster than creating hundreds of Rectangle shapes.
        Canvas { context, size in

            // Use the current theme's border color, made very faint (20% opacity)
            // so the lines are visible but not distracting.
            let lineColor = themeManager.currentTheme.border.opacity(0.6)
            var path = Path()

            var y = spacing.lineInterval
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing.lineInterval
            }

            context.stroke(path, with: .color(lineColor), lineWidth: 0.75)
        }
        .allowsHitTesting(false)  // lines never block touches — they're purely visual
        .ignoresSafeArea()
    }
}
