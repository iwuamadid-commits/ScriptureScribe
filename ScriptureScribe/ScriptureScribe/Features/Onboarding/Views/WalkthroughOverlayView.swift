//
//  WalkthroughOverlayView.swift
//  ScriptureScribe
//
//  Full-screen spotlight overlay for the interactive walkthrough.
//
//  Touch pass-through architecture:
//    ContentView renders TWO separate overlay layers:
//      1. WalkthroughDimOverlay  — visual only, .allowsHitTesting(false) on the
//         entire view. Shows dim, spotlight cutout, tooltip text, badge, counter.
//      2. WalkthroughControlsOverlay — contains ONLY the Back, Next, and Skip
//         buttons. Because these are small views in an otherwise-empty ZStack,
//         touches in empty areas fall through to the TabView underneath.
//    This guarantees long-press, context menus, and swipe gestures work on the
//    underlying views during the walkthrough.
//

import SwiftUI

// MARK: - Spotlight Cutout View

/// Punches a clear rounded-rect hole through the dim overlay.
/// Position and size animate smoothly between regular steps.
/// Fades in/out when appearing or disappearing (tab-switch transitions).
struct SpotlightCutout: View {
    let cutout: CGRect
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .frame(width: cutout.width, height: cutout.height)
            .position(x: cutout.midX, y: cutout.midY)
            .blendMode(.destinationOut)
            .transition(.opacity)
    }
}

// MARK: - Shared Helpers

/// Shared logic used by both the dim and controls overlays.
enum WalkthroughLayout {

    static func targetFrame(
        for step: WalkthroughStep,
        manager: WalkthroughManager,
        screenSize: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> CGRect {
        if step.isTabBarTarget, let slot = step.tabBarSlot {
            return manager.tabBarFrame(slot: slot, screenSize: screenSize, safeAreaTop: safeAreaTop, safeAreaBottom: safeAreaBottom)
        }
        if step.isToolbarTarget, let edge = step.toolbarEdge {
            return manager.toolbarButtonFrame(edge: edge, screenSize: screenSize, safeAreaTop: safeAreaTop)
        }
        return manager.anchorFrames[step.id]
            ?? CGRect(x: screenSize.width / 2, y: screenSize.height / 2, width: 100, height: 50)
    }

    static func tooltipY(step: WalkthroughStep, frame: CGRect, screenHeight: CGFloat) -> CGFloat {
        let isAbove = step.tooltipEdge == .top
        let raw = isAbove
            ? frame.minY - step.spotlightPadding - 100
            : frame.maxY + step.spotlightPadding + 100
        return max(80, min(raw, screenHeight - 120))
    }

    static func clampX(_ x: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let halfW = min(screenWidth - 40, 360) / 2
        return min(max(x, halfW + 20), screenWidth - halfW - 20)
    }
}

// MARK: - Layer 1: Visual Only (dim + spotlight + tooltip text)

struct WalkthroughDimOverlay: View {

    @ObservedObject var manager: WalkthroughManager
    @EnvironmentObject private var themeManager: ThemeManager

    private var theme: any AppTheme { themeManager.currentTheme }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let top = geo.safeAreaInsets.top
            let bottom = geo.safeAreaInsets.bottom
            if let step = manager.currentStep {
                if step.isCompletion {
                    Color.black.opacity(0.65)
                } else {
                    let hasSpotlight = !step.isTabBarTarget
                    let frame = hasSpotlight
                        ? WalkthroughLayout.targetFrame(
                            for: step, manager: manager,
                            screenSize: size, safeAreaTop: top, safeAreaBottom: bottom
                        )
                        : .zero
                    let tipX = hasSpotlight ? WalkthroughLayout.clampX(frame.midX, screenWidth: size.width) : size.width / 2
                    let tipY = hasSpotlight ? WalkthroughLayout.tooltipY(step: step, frame: frame, screenHeight: size.height) : size.height / 2

                    // Dim + spotlight cutout in a compositing group so
                    // .destinationOut punches through the dim correctly.
                    ZStack {
                        Color.black.opacity(0.65)

                        if hasSpotlight {
                            SpotlightCutout(
                                cutout: cutoutRect(step: step, frame: frame),
                                cornerRadius: step.spotlightCornerRadius
                            )
                        }
                    }
                    .compositingGroup()

                    // Tooltip visual — each step gets its own identity so
                    // SwiftUI fades it in at the destination instead of
                    // gliding the box while the text changes mid-flight.
                    tooltipVisual(step: step, tipX: tipX, tipY: tipY, maxW: min(size.width - 40, 360))
                        .id(manager.currentStepIndex)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.1)),
                            removal:   .opacity.animation(.easeIn(duration: 0.15))
                        ))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false) // ALL touches pass through this layer
    }

    // MARK: Spotlight

    private func cutoutRect(step: WalkthroughStep, frame: CGRect) -> CGRect {
        let pad = step.spotlightPadding
        return CGRect(
            x: frame.midX - (frame.width + pad * 2) / 2,
            y: frame.midY - (frame.height + pad * 2) / 2,
            width: frame.width + pad * 2,
            height: frame.height + pad * 2
        )
    }

    // MARK: Tooltip Visual

    private func tooltipVisual(step: WalkthroughStep, tipX: CGFloat, tipY: CGFloat, maxW: CGFloat) -> some View {
        VStack(spacing: 12) {
            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(Color(theme.text))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if step.isInteractive {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption2)
                    Text("Try it!")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color(theme.primary))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(theme.primary).opacity(0.12), in: Capsule())
            }

            // Bottom row: < counter >
            HStack {
                // Back arrow placeholder (invisible — real button is in controls layer)
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(manager.currentStepIndex > 0 ? Color(theme.textSecondary) : .clear)
                    .frame(width: 32, height: 32)

                Spacer()

                Text("\(manager.currentStepIndex + 1) of \(manager.totalSteps - 1)")
                    .font(.caption)
                    .foregroundStyle(Color(theme.textSecondary))

                Spacer()

                // Next arrow (visual only — real button is in controls layer)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(theme.primary))
                    .frame(width: 32, height: 32)
            }
        }
        .padding(16)
        .frame(maxWidth: maxW)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(theme.surface))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        )
        .fixedSize()
        .position(x: tipX, y: tipY)
    }

}

// MARK: - Layer 2: Controls Only (Back, Next, Skip buttons)

struct WalkthroughControlsOverlay: View {

    @ObservedObject var manager: WalkthroughManager
    @EnvironmentObject private var themeManager: ThemeManager

    private var theme: any AppTheme { themeManager.currentTheme }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let top = geo.safeAreaInsets.top
            let bottom = geo.safeAreaInsets.bottom
            if let step = manager.currentStep {
                if step.isCompletion {
                    completionCard()
                } else {
                    let frame = step.isTabBarTarget ? nil : WalkthroughLayout.targetFrame(
                        for: step, manager: manager,
                        screenSize: size, safeAreaTop: top, safeAreaBottom: bottom
                    )
                    let tipX = step.isTabBarTarget ? size.width / 2 : WalkthroughLayout.clampX(frame!.midX, screenWidth: size.width)
                    let tipY = step.isTabBarTarget ? size.height / 2 : WalkthroughLayout.tooltipY(step: step, frame: frame!, screenHeight: size.height)

                    // Back + Next buttons — matches tooltip position and transitions.
                    controlStrip(tipX: tipX, tipY: tipY, maxW: min(size.width - 40, 360), step: step)
                        .id(manager.currentStepIndex)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.1)),
                            removal:   .opacity.animation(.easeIn(duration: 0.15))
                        ))

                    // Skip button — bottom-right corner
                    Button("Skip") { manager.skip() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(12)
                        .contentShape(Rectangle())
                        .position(
                            x: size.width - 50,
                            y: size.height - bottom - 36
                        )
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Renders just the Back and Next buttons, sized and positioned to match
    /// the tooltip visual's bottom row.
    @ViewBuilder
    private func controlStrip(tipX: CGFloat, tipY: CGFloat, maxW: CGFloat, step: WalkthroughStep) -> some View {
        // We need to compute the vertical offset from the tooltip center to the
        // bottom button row. We use an overlay with a hidden measuring tooltip.
        // Simpler approach: use a known offset based on content.
        //
        // Tooltip content height ≈ message + optional badge + button row + padding.
        // The buttons sit at the bottom. We calculate the tooltip height by mirroring
        // the visual structure with hidden text, then position the buttons.

        // Build the same VStack structure but invisible, just to get the height.
        // Then overlay the real buttons at the bottom.
        VStack(spacing: 12) {
            // Mirror the message text
            Text(step.message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()

            if step.isInteractive {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill").font(.caption2)
                    Text("Try it!").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .hidden()
            }

            // Real buttons (not hidden)
            HStack {
                Button(action: { manager.previous() }) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.clear) // invisible — visual layer shows this
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .opacity(manager.currentStepIndex > 0 ? 1 : 0)
                .disabled(manager.currentStepIndex == 0)

                Spacer()

                // Invisible counter placeholder — keeps layout matching visual layer
                Text("\(manager.currentStepIndex + 1) of \(manager.totalSteps - 1)")
                    .font(.caption)
                    .foregroundStyle(.clear)
                    .allowsHitTesting(false)

                Spacer()

                Button(action: { manager.next() }) {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.clear) // invisible — visual layer shows this
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: maxW)
        .fixedSize()
        .position(x: tipX, y: tipY)
    }

    // MARK: Completion Card

    @ViewBuilder
    private func completionCard() -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(theme.primary).opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(Color(theme.primary))
            }

            Text("You're All Set!")
                .font(.title.bold())
                .foregroundStyle(Color(theme.text))

            Text("Enjoy Scripture Scribe.")
                .font(.body)
                .foregroundStyle(Color(theme.textSecondary))

            Button(action: { manager.complete() }) {
                Text("Start Reading")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
                    .background(Color(theme.primary))
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(theme.surface))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
