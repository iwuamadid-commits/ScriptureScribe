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
        // Coach marks report in "walkthrough" coordinate space (TabView,
        // safe-area-inset origin) but overlays use .ignoresSafeArea() (window
        // origin). Offset Y by safeAreaTop to compensate.
        if var frame = manager.anchorFrames[step.id] {
            frame.origin.y += safeAreaTop
            return frame
        }
        return CGRect(x: screenSize.width / 2, y: screenSize.height / 2, width: 100, height: 50)
    }

    /// Where the tooltip's centre goes. iPad keeps its original placement; iPhone
    /// measures the tooltip and keeps it on screen and off what it points at.
    static func tooltipCenterY(
        step: WalkthroughStep,
        frame: CGRect,
        screenSize: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat,
        maxW: CGFloat
    ) -> CGFloat {
        if step.isTabBarTarget { return screenSize.height / 2 }
        if DeviceCapabilities.isPhoneLayout {
            return phoneTooltipY(step: step, frame: frame, screenSize: screenSize,
                                 safeAreaTop: safeAreaTop, safeAreaBottom: safeAreaBottom, maxW: maxW)
        }
        return tooltipY(step: step, frame: frame, screenHeight: screenSize.height)
    }

    /// iPhone placement. `tooltipY` assumes every tooltip is about two lines tall,
    /// which holds on iPad but not on a phone, where longer messages wrap further
    /// and the tooltip spilled over its target or off the top of the screen.
    ///
    /// Goes on the step's preferred side if it fits there, else the other side.
    /// When neither fits (the target fills the screen, like the Bible text), it
    /// sits over the target at the bottom of the screen, clear of the tab bar.
    private static func phoneTooltipY(
        step: WalkthroughStep,
        frame: CGRect,
        screenSize: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat,
        maxW: CGFloat
    ) -> CGFloat {
        let height = phoneTooltipHeight(step: step, maxW: maxW)
        let gap: CGFloat = 12
        let topLimit = safeAreaTop + 4
        let bottomLimit = screenSize.height - max(safeAreaBottom, 8) - 58   // above the tab bar
        let cutout = frame.insetBy(dx: -step.spotlightPadding, dy: -step.spotlightPadding)

        let belowY = cutout.maxY + gap + height / 2
        let aboveY = cutout.minY - gap - height / 2
        let fitsBelow = belowY + height / 2 <= bottomLimit
        let fitsAbove = aboveY - height / 2 >= topLimit

        let y: CGFloat
        if step.tooltipEdge == .bottom {
            y = fitsBelow ? belowY : fitsAbove ? aboveY : bottomLimit - height / 2
        } else {
            y = fitsAbove ? aboveY : fitsBelow ? belowY : bottomLimit - height / 2
        }
        return min(max(y, topLimit + height / 2), bottomLimit - height / 2)
    }

    /// The tooltip's height on iPhone, worked out the same way it lays out:
    /// padding, the message wrapped to the tooltip's width, the optional
    /// "Try it!" badge, the arrow row and the Skip row.
    static func phoneTooltipHeight(step: WalkthroughStep, maxW: CGFloat) -> CGFloat {
        let message = (step.message as NSString).boundingRect(
            with: CGSize(width: maxW - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline)],
            context: nil
        ).height
        let caption = UIFont.preferredFont(forTextStyle: .caption1).lineHeight
        let badge = step.isInteractive ? 12 + ceil(caption) + 8 : 0
        return 16 + ceil(message) + badge + 12 + 32 + 2 + phoneSkipRowHeight + 16
    }

    /// The Skip row inside the iPhone tooltip.
    static let phoneSkipRowHeight: CGFloat = 22

    static func tooltipY(step: WalkthroughStep, frame: CGRect, screenHeight: CGFloat) -> CGFloat {
        let pad = step.spotlightPadding
        let tooltipHalfHeight: CGFloat = 70 // approximate half-height of tooltip card
        let isAbove = step.tooltipEdge == .top

        if isAbove {
            // Place tooltip center above the cutout top edge with enough clearance
            let cutoutTop = frame.minY - pad
            let raw = cutoutTop - tooltipHalfHeight - 12
            return max(80, min(raw, screenHeight - 120))
        } else {
            // Place tooltip center below the cutout bottom edge with enough clearance
            let cutoutBottom = frame.maxY + pad
            let raw = cutoutBottom + tooltipHalfHeight + 12
            return max(80, min(raw, screenHeight - 120))
        }
    }

    static func clampX(_ x: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let halfW = min(screenWidth - 40, 360) / 2
        return min(max(x, halfW + 20), screenWidth - halfW - 20)
    }
}

extension View {
    /// Sizes a tooltip (and its invisible twin in the controls layer, so the
    /// buttons line up). iPad: as wide as its message needs, up to `maxW`.
    /// iPhone: always `maxW` wide and as tall as the wrapped message needs.
    /// Sized the iPad way, the box was laid out for one line of text, and a
    /// message that wraps to three lines on a phone spilled out of it.
    @ViewBuilder
    func walkthroughTooltipFrame<Background: View>(
        maxW: CGFloat,
        @ViewBuilder background: () -> Background
    ) -> some View {
        if DeviceCapabilities.isPhoneLayout {
            frame(width: maxW)
                .background(background())
                .fixedSize(horizontal: false, vertical: true)
        } else {
            frame(maxWidth: maxW)
                .background(background())
                .fixedSize()
        }
    }
}

// MARK: - Layer 1: Visual Only (dim + spotlight + tooltip text)

struct WalkthroughDimOverlay: View {

    @ObservedObject var manager: WalkthroughManager
    @EnvironmentObject private var themeManager: ThemeManager

    private var theme: any AppTheme { themeManager.currentTheme }

    var body: some View {
        ZStack {
            // Spotlight steps layer — visible when not on welcome card
            GeometryReader { geo in
                let size = geo.size
                let top = geo.safeAreaInsets.top
                let bottom = geo.safeAreaInsets.bottom
                if let step = manager.currentStep {
                    if step.isCompletion {
                        Color.black.opacity(0.45)
                    } else {
                        let frame = WalkthroughLayout.targetFrame(
                            for: step, manager: manager,
                            screenSize: size, safeAreaTop: top, safeAreaBottom: bottom
                        )
                        let tipX = step.isTabBarTarget ? size.width / 2 : WalkthroughLayout.clampX(frame.midX, screenWidth: size.width)
                        let tipY = WalkthroughLayout.tooltipCenterY(
                            step: step, frame: frame, screenSize: size,
                            safeAreaTop: top, safeAreaBottom: bottom, maxW: min(size.width - 40, 360)
                        )

                        ZStack {
                            Color.black.opacity(0.45)

                            SpotlightCutout(
                                cutout: cutoutRect(step: step, frame: frame),
                                cornerRadius: step.spotlightCornerRadius
                            )
                        }
                        .compositingGroup()

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

            // White fade — sits on top of everything during transition
            Color.white
                .ignoresSafeArea()
                .opacity(manager.showWhiteFade ? 1 : 0)
                .animation(manager.showWhiteFade ? nil : .easeOut(duration: 1.0), value: manager.showWhiteFade)
        }
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

            VStack(spacing: 2) {
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

                // iPhone: Skip lives in the tooltip (real button in controls layer).
                // In the screen's corner it covered the last tab and whatever
                // else was there.
                if DeviceCapabilities.isPhoneLayout {
                    Text("Skip tour")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(theme.textSecondary))
                        .frame(height: WalkthroughLayout.phoneSkipRowHeight)
                }
            }
        }
        .padding(16)
        .walkthroughTooltipFrame(maxW: maxW) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(theme.surface))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
        .position(x: tipX, y: tipY)
    }

}

// MARK: - Layer 2: Controls Only (Back, Next, Skip buttons)

struct WalkthroughControlsOverlay: View {

    @ObservedObject var manager: WalkthroughManager
    @EnvironmentObject private var themeManager: ThemeManager

    private var theme: any AppTheme { themeManager.currentTheme }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = geo.size
                let top = geo.safeAreaInsets.top
                let bottom = geo.safeAreaInsets.bottom

                // Full-screen touch blocker
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { }

                // Spotlight step controls
                if let step = manager.currentStep {
                    if step.isCompletion {
                        completionCard()
                    } else {
                        let frame = WalkthroughLayout.targetFrame(
                            for: step, manager: manager,
                            screenSize: size, safeAreaTop: top, safeAreaBottom: bottom
                        )
                        let tipX = step.isTabBarTarget ? size.width / 2 : WalkthroughLayout.clampX(frame.midX, screenWidth: size.width)
                        let tipY = WalkthroughLayout.tooltipCenterY(
                            step: step, frame: frame, screenSize: size,
                            safeAreaTop: top, safeAreaBottom: bottom, maxW: min(size.width - 40, 360)
                        )

                        controlStrip(tipX: tipX, tipY: tipY, maxW: min(size.width - 40, 360), step: step)
                            .id(manager.currentStepIndex)
                            .transition(.asymmetric(
                                insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.1)),
                                removal:   .opacity.animation(.easeIn(duration: 0.15))
                            ))

                        // iPad only: on iPhone, Skip is inside the tooltip.
                        if !DeviceCapabilities.isPhoneLayout {
                            Button("Skip") { manager.skip() }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(theme.textSecondary))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .contentShape(Rectangle())
                                .position(
                                    x: size.width - 55,
                                    y: size.height - bottom - 36
                                )
                        }
                    }
                }

            }
            .ignoresSafeArea()

            // Welcome card — separate layer, uses opacity for smooth fade
            welcomeCard()
                .opacity(manager.showWelcomeCard ? 1 : 0)
                .animation(.easeInOut(duration: 0.8), value: manager.showWelcomeCard)
                .allowsHitTesting(manager.showWelcomeCard)
        }
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

            VStack(spacing: 2) {
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

                if DeviceCapabilities.isPhoneLayout {
                    Button(action: { manager.skip() }) {
                        Text("Skip tour")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.clear) // invisible — visual layer shows this
                            .frame(height: WalkthroughLayout.phoneSkipRowHeight)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Skip tour")
                }
            }
        }
        .padding(16)
        .walkthroughTooltipFrame(maxW: maxW) { Color.clear }
        .position(x: tipX, y: tipY)
    }

    // MARK: Completion Card

    // MARK: Welcome Card

    @ViewBuilder
    private func welcomeCard() -> some View {
        Color(theme.background)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 24) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color(theme.primary).opacity(0.12))
                            .frame(width: 120, height: 120)
                        Image(systemName: "book.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Color(theme.primary))
                    }

                    Text("Welcome to\nScripture Scribe!")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color(theme.text))
                        .multilineTextAlignment(.center)

                    Text("Let us show you around so you can\nget the most out of the app.")
                        .font(.body)
                        .foregroundStyle(Color(theme.textSecondary))
                        .multilineTextAlignment(.center)

                    Spacer()

                    VStack(spacing: 14) {
                        Button(action: { manager.beginTour() }) {
                            Text("Let's Take a Tour")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: 300)
                                .padding(.vertical, 16)
                                .background(Color(theme.primary))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: { manager.skipTour() }) {
                            Text("Skip")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(theme.textSecondary))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 50)
                }
                .padding(.horizontal, 32)
            }
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
