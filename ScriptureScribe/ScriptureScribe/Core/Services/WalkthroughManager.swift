//
//  WalkthroughManager.swift
//  ScriptureScribe
//
//  Drives the interactive spotlight walkthrough that guides first-time users
//  through the app's main features. Each step highlights a real UI element
//  and shows a tooltip with a brief description.
//

import Combine
import SwiftUI

// MARK: - Step Definition

enum TooltipEdge { case top, bottom }
enum ToolbarEdge { case leading, trailing }

struct WalkthroughStep {
    let id: String                       // matches the coachMark anchor ID
    let targetTab: Int                   // which tab this element lives on
    let switchToTab: Int?                // if set, switch to this tab BEFORE showing
    let message: String
    let tooltipEdge: TooltipEdge
    let spotlightPadding: CGFloat
    let spotlightCornerRadius: CGFloat
    let isTabBarTarget: Bool             // true -> compute frame from tab bar position
    let tabBarSlot: Int?                 // which tab bar slot (0-5) to spotlight
    let isToolbarTarget: Bool            // true -> compute frame from nav bar position
    let toolbarEdge: ToolbarEdge?        // .leading or .trailing
    let isInteractive: Bool              // true -> user can interact with the spotlighted element
    let isCompletion: Bool               // true -> centered card, no spotlight
}

extension WalkthroughStep {
    /// Convenience init for normal content steps.
    static func content(
        id: String, tab: Int, message: String,
        edge: TooltipEdge = .bottom,
        padding: CGFloat = 12, radius: CGFloat = 12
    ) -> WalkthroughStep {
        WalkthroughStep(
            id: id, targetTab: tab, switchToTab: nil,
            message: message, tooltipEdge: edge,
            spotlightPadding: padding, spotlightCornerRadius: radius,
            isTabBarTarget: false, tabBarSlot: nil,
            isToolbarTarget: false, toolbarEdge: nil,
            isInteractive: false, isCompletion: false
        )
    }

    /// Convenience init for interactive steps (user can touch the spotlighted element).
    static func interactive(
        id: String, tab: Int, message: String,
        edge: TooltipEdge = .bottom,
        padding: CGFloat = 12, radius: CGFloat = 12
    ) -> WalkthroughStep {
        WalkthroughStep(
            id: id, targetTab: tab, switchToTab: nil,
            message: message, tooltipEdge: edge,
            spotlightPadding: padding, spotlightCornerRadius: radius,
            isTabBarTarget: false, tabBarSlot: nil,
            isToolbarTarget: false, toolbarEdge: nil,
            isInteractive: true, isCompletion: false
        )
    }

    /// Convenience init for toolbar-hosted buttons (frame computed, not reported).
    static func toolbar(
        id: String, tab: Int, message: String,
        edge: ToolbarEdge = .trailing,
        tooltipEdge: TooltipEdge = .bottom,
        padding: CGFloat = 10, radius: CGFloat = 22
    ) -> WalkthroughStep {
        WalkthroughStep(
            id: id, targetTab: tab, switchToTab: nil,
            message: message, tooltipEdge: tooltipEdge,
            spotlightPadding: padding, spotlightCornerRadius: radius,
            isTabBarTarget: false, tabBarSlot: nil,
            isToolbarTarget: true, toolbarEdge: edge,
            isInteractive: false, isCompletion: false
        )
    }

    /// Convenience init for tab bar spotlight + tab switch steps.
    static func tabSwitch(
        slot: Int, switchTo: Int, message: String
    ) -> WalkthroughStep {
        WalkthroughStep(
            id: "tab-bar-\(slot)", targetTab: -1, switchToTab: switchTo,
            message: message, tooltipEdge: .top,
            spotlightPadding: 4, spotlightCornerRadius: 16,
            isTabBarTarget: true, tabBarSlot: slot,
            isToolbarTarget: false, toolbarEdge: nil,
            isInteractive: false, isCompletion: false
        )
    }

    /// The final "You're all set!" card.
    static var completion: WalkthroughStep {
        WalkthroughStep(
            id: "completion", targetTab: -1, switchToTab: nil,
            message: "", tooltipEdge: .bottom,
            spotlightPadding: 0, spotlightCornerRadius: 0,
            isTabBarTarget: false, tabBarSlot: nil,
            isToolbarTarget: false, toolbarEdge: nil,
            isInteractive: false, isCompletion: true
        )
    }
}

// MARK: - Manager

final class WalkthroughManager: ObservableObject {

    // MARK: Published state

    @Published var isActive: Bool = false
    @Published var currentStepIndex: Int = 0
    @Published var anchorFrames: [String: CGRect] = [:]
    /// True while switching tabs — hides overlays so the old step doesn't linger.
    @Published var isTransitioning: Bool = false

    // MARK: Navigation hook

    /// Set by ContentView so the manager can switch tabs.
    weak var appNav: AppNavigation?

    // MARK: Step list

    let steps: [WalkthroughStep] = [
        // Reader tab — feature-specific spotlights
        .interactive(id: "reader-verse-row", tab: 0,
                     message: "Press and hold any verse to bookmark it or start a selection.",
                     padding: 8, radius: 12),

        .interactive(id: "reader-selected-book", tab: 0,
                     message: "Tap the selected book again to browse all books.",
                     padding: 6, radius: 20),

        .content(id: "reader-sort-button", tab: 0,
                 message: "Switch between Bible order and A–Z with this button.",
                 padding: 8, radius: 16),

        .interactive(id: "reader-bible-text", tab: 0,
                     message: "Double-tap anywhere on the page to create a typed note.",
                     padding: 8, radius: 16),

        .content(id: "reader-annotation-toolbar", tab: 0,
                 message: "Draw, highlight, erase, and lasso to select and move your annotations.",
                 edge: .bottom, padding: 6, radius: 16),

        .content(id: "reader-color-swatches", tab: 0,
                 message: "Tap '+' to save new colors. Tap a swatch to select, or long-press to rearrange.",
                 edge: .bottom, padding: 6, radius: 12),

        // Daily tab
        .tabSwitch(slot: 1, switchTo: 1,
                   message: "Let's explore the Daily tab."),

        .interactive(id: "daily-section-card", tab: 1,
                     message: "Press and hold any section to rearrange your Daily page.",
                     padding: 8, radius: 16),

        // Habits tab
        .tabSwitch(slot: 2, switchTo: 2,
                   message: "Now let's check out Habits."),

        .content(id: "habits-add-button", tab: 2,
                 message: "Tap '+' to create a custom habit or choose from suggestions.",
                 edge: .bottom, padding: 10, radius: 22),

        // Community tab
        .tabSwitch(slot: 3, switchTo: 3,
                   message: "Next up: Community."),

        // Walk through each community sub-tab individually
        .content(id: "community-insights-tab", tab: 3,
                 message: "Share what God is teaching you through Scripture in the Insights section.",
                 padding: 6, radius: 20),

        .content(id: "community-gratitude-tab", tab: 3,
                 message: "Post what you're thankful for in Gratitude, with optional photos.",
                 padding: 6, radius: 20),

        .content(id: "community-prayer-tab", tab: 3,
                 message: "Share prayer requests and support others in the Prayer section.",
                 padding: 6, radius: 20),

        .content(id: "community-daily-tab", tab: 3,
                 message: "Answer the daily question and see how others responded.",
                 padding: 6, radius: 20),

        .content(id: "community-compose-button", tab: 3,
                 message: "Tap the pencil icon to post to the current section.",
                 edge: .bottom, padding: 10, radius: 22),

        // Library tab
        .tabSwitch(slot: 4, switchTo: 4,
                   message: "Finally, let's check your Library."),

        .content(id: "saved-sort-button", tab: 4,
                 message: "Sort your bookmark collections by 'Last Added' or 'A–Z'.",
                 edge: .bottom, padding: 10, radius: 22),

        // Done
        .completion,
    ]

    var currentStep: WalkthroughStep? {
        guard isActive, !isTransitioning, steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    var totalSteps: Int { steps.count }

    // MARK: Actions

    /// Starts the walkthrough once the reader content is loaded.
    /// Polls for the first step's coach mark frame before showing the overlay.
    func start() {
        currentStepIndex = 0
        appNav?.selectedTab = 0
        waitForReaderThenActivate()
    }

    private func waitForReaderThenActivate() {
        // The coach mark frame for the first verse is reported only after
        // the Bible text loads. Poll briefly until it appears.
        if anchorFrames["reader-verse-row"] != nil {
            // Reader content is loaded. The reader's own fade-in takes
            // ~0.35s delay + 0.3s easeIn. Wait for that to finish, then
            // fade in the walkthrough overlay so it layers on smoothly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.isActive = true
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.waitForReaderThenActivate()
            }
        }
    }

    /// Shared animation curve used for every step transition.
    /// Smooth spring with no bounce for a premium glide feel.
    static let stepAnimation: Animation = .spring(duration: 0.45, bounce: 0)

    func next() {
        let nextIndex = currentStepIndex + 1
        guard nextIndex < steps.count else { complete(); return }

        let nextStep = steps[nextIndex]

        if let switchTo = nextStep.switchToTab {
            // Hide old step immediately, switch tab, then animate in the new step.
            withAnimation(.easeIn(duration: 0.15)) {
                isTransitioning = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.currentStepIndex = nextIndex
                self?.appNav?.selectedTab = switchTo
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                withAnimation(Self.stepAnimation) {
                    self?.isTransitioning = false
                }
            }
        } else {
            withAnimation(Self.stepAnimation) {
                currentStepIndex = nextIndex
            }
        }
    }

    func previous() {
        let prevIndex = currentStepIndex - 1
        guard prevIndex >= 0 else { return }

        let prevStep = steps[prevIndex]
        let currentStep = steps[currentStepIndex]

        // Figure out which tab the previous step lives on.
        let prevTab = prevStep.targetTab >= 0 ? prevStep.targetTab : nil
        let needsTabSwitch = prevTab != nil && prevTab != (currentStep.targetTab >= 0 ? currentStep.targetTab : nil)

        if needsTabSwitch, let tab = prevTab {
            // Hide old step immediately, switch tab, then animate in the previous step.
            withAnimation(.easeIn(duration: 0.15)) {
                isTransitioning = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.currentStepIndex = prevIndex
                self?.appNav?.selectedTab = tab
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                withAnimation(Self.stepAnimation) {
                    self?.isTransitioning = false
                }
            }
        } else {
            withAnimation(Self.stepAnimation) {
                currentStepIndex = prevIndex
            }
        }
    }

    func skip() {
        complete()
    }

    func complete() {
        // Fade out the completion card first
        withAnimation(.easeOut(duration: 0.3)) {
            isTransitioning = true
        }
        // After the card fades, switch to the reader tab and dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.appNav?.selectedTab = 0
            withAnimation(.easeOut(duration: 0.4)) {
                self?.isActive = false
            }
            self?.currentStepIndex = 0
            self?.isTransitioning = false
        }
    }

    // MARK: - Tab Bar Frame Calculation

    /// Computes the spotlight frame for a tab bar item slot.
    /// iPad: compact top tab bar (labels sit in the status bar / navigation chrome).
    /// iPhone: standard bottom tab bar.
    func tabBarFrame(slot: Int, screenSize: CGSize, safeAreaTop: CGFloat, safeAreaBottom: CGFloat) -> CGRect {
        let tabCount: CGFloat = 6
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        if isIPad {
            // iPad: the compact top tab bar renders tab labels in the navigation
            // chrome area at the very top of the screen. Positions are measured
            // as percentages of screen width so they scale across iPad sizes.
            // Each slot's X center as a fraction of screen width (calibrated from
            // iPad Pro 12.9" landscape — approximate, varies slightly with label width).
            let slotFractions: [CGFloat] = [0.21, 0.248, 0.284, 0.332, 0.382, 0.425]
            let fraction = slot < slotFractions.count ? slotFractions[slot] : 0.5
            let centerX = screenSize.width * fraction
            // Tab labels sit at the vertical midpoint of the top chrome area
            let centerY: CGFloat = safeAreaTop > 40 ? safeAreaTop / 2 : 25
            let spotW: CGFloat = 70
            let spotH: CGFloat = 36
            return CGRect(
                x: centerX - spotW / 2,
                y: centerY - spotH / 2,
                width: spotW,
                height: spotH
            )
        } else {
            // iPhone: standard bottom tab bar
            let slotWidth = screenSize.width / tabCount
            let tabBarHeight: CGFloat = 49
            let centerX = (CGFloat(slot) + 0.5) * slotWidth
            let centerY = screenSize.height - safeAreaBottom - tabBarHeight / 2
            let spotW: CGFloat = slotWidth * 0.8
            let spotH: CGFloat = tabBarHeight - 4
            return CGRect(
                x: centerX - spotW / 2,
                y: centerY - spotH / 2,
                width: spotW,
                height: spotH
            )
        }
    }

    // MARK: - Toolbar Button Frame Calculation

    /// Computes the spotlight frame for a navigation bar button.
    func toolbarButtonFrame(edge: ToolbarEdge, screenSize: CGSize, safeAreaTop: CGFloat) -> CGRect {
        let size: CGFloat = 44
        let centerY = safeAreaTop + 22
        let centerX: CGFloat
        switch edge {
        case .trailing: centerX = screenSize.width - 38
        case .leading:  centerX = 38
        }
        return CGRect(
            x: centerX - size / 2,
            y: centerY - size / 2,
            width: size,
            height: size
        )
    }
}
