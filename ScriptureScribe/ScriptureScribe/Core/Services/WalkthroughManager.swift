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
    var communitySubTab: Int?            // if set, switch community sub-tab via pendingCommunityTab
    var savedSubTab: Int?                // if set, switch library sub-tab via pendingSavedTab
}

extension WalkthroughStep {
    /// Convenience init for normal content steps.
    static func content(
        id: String, tab: Int, message: String,
        edge: TooltipEdge = .bottom,
        padding: CGFloat = 12, radius: CGFloat = 12,
        communitySubTab: Int? = nil,
        savedSubTab: Int? = nil
    ) -> WalkthroughStep {
        WalkthroughStep(
            id: id, targetTab: tab, switchToTab: nil,
            message: message, tooltipEdge: edge,
            spotlightPadding: padding, spotlightCornerRadius: radius,
            isTabBarTarget: false, tabBarSlot: nil,
            isToolbarTarget: false, toolbarEdge: nil,
            isInteractive: false, isCompletion: false,
            communitySubTab: communitySubTab,
            savedSubTab: savedSubTab
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
            isInteractive: true, isCompletion: false,
            communitySubTab: nil, savedSubTab: nil
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
            isInteractive: false, isCompletion: false,
            communitySubTab: nil, savedSubTab: nil
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
            isInteractive: false, isCompletion: false,
            communitySubTab: nil, savedSubTab: nil
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
            isInteractive: false, isCompletion: true,
            communitySubTab: nil, savedSubTab: nil
        )
    }
}

// MARK: - Manager

final class WalkthroughManager: ObservableObject {

    // MARK: Published state

    @Published var isActive: Bool = false
    @Published var showWelcomeCard: Bool = false
    @Published var showWhiteFade: Bool = false
    @Published var currentStepIndex: Int = 0
    @Published var anchorFrames: [String: CGRect] = [:]
    /// True while switching tabs — hides overlays so the old step doesn't linger.
    @Published var isTransitioning: Bool = false

    // MARK: Navigation hook

    /// Set by ContentView so the manager can switch tabs.
    weak var appNav: AppNavigation?

    // MARK: Step list

    let steps: [WalkthroughStep] = [
        // Reader tab — introduction, then navigation, then reading, then tools
        .content(id: "reader-bible-text", tab: 0,
                 message: "This is your Reader, where you'll read, annotate, and study Scripture.",
                 edge: .top, padding: 8, radius: 16),

        .content(id: "reader-version-button", tab: 0,
                 message: "Tap here to switch Bible translations like KJV, NIV, ESV, and more.",
                 edge: .bottom, padding: 10, radius: 14),

        .content(id: "reader-selected-book", tab: 0,
                 message: "This is the book you're reading. Tap it to browse all books.",
                 padding: 6, radius: 10),

        .content(id: "reader-sort-button", tab: 0,
                 message: "Switch between Bible order and A to Z.",
                 padding: 8, radius: 8),

        .content(id: "reader-chapter-row", tab: 0,
                 message: "Scroll through chapters here. Tap any number to jump to it.",
                 padding: 6, radius: 10),

        .content(id: "reader-annotation-toolbar", tab: 0,
                 message: "Draw, highlight, erase, and lasso to select and move your annotations.",
                 edge: .bottom, padding: 6, radius: 16),

        .content(id: "reader-color-swatches", tab: 0,
                 message: "Tap '+' to save new colors. Tap a swatch to select, or long-press to rearrange.",
                 edge: .bottom, padding: 6, radius: 12),

        .content(id: "reader-verse-row", tab: 0,
                 message: "Press and hold any verse to bookmark it or start a selection.",
                 padding: 8, radius: 12),

        .content(id: "reader-bible-text", tab: 0,
                 message: "Double-tap anywhere on the page to create a typed note.",
                 edge: .top, padding: 8, radius: 16),

        // Daily tab
        .tabSwitch(slot: 1, switchTo: 1,
                   message: "Let's explore the Daily tab."),

        .content(id: "daily-verse-section", tab: 1,
                 message: "Your Verse of the Day. You can tap it to open it in the reader.",
                 padding: 8, radius: 16),

        .content(id: "daily-affirmation-section", tab: 1,
                 message: "A personalized affirmation inspired by today's verse.",
                 padding: 8, radius: 16),

        .content(id: "daily-prayer-section", tab: 1,
                 message: "A guided prayer to help you reflect on the verse.",
                 padding: 8, radius: 16),

        .content(id: "daily-devotion-section", tab: 1,
                 message: "A short devotion exploring the meaning behind the verse.",
                 padding: 8, radius: 16),

        .content(id: "daily-reflection-section", tab: 1,
                 message: "Journal your thoughts with a guided reflection prompt.",
                 edge: .top, padding: 8, radius: 16),

        // Habits tab
        .tabSwitch(slot: 2, switchTo: 2,
                   message: "Now let's check out Habits."),

        .content(id: "habits-card", tab: 2,
                 message: "Tap a habit to mark it complete. Track your progress each day.",
                 padding: 8, radius: 18),

        .content(id: "habits-add-button", tab: 2,
                 message: "Tap '+' to create a custom habit or choose from suggestions.",
                 edge: .bottom, padding: 14, radius: 50),

        // Community tab
        .tabSwitch(slot: 3, switchTo: 3,
                   message: "Next up: Community."),

        // Walk through each community sub-tab individually
        .content(id: "community-insights-tab", tab: 3,
                 message: "Share what God is teaching you through Scripture in the Insights section.",
                 padding: 6, radius: 20, communitySubTab: 0),

        .content(id: "community-gratitude-tab", tab: 3,
                 message: "Post what you're thankful for in Gratitude, with optional photos.",
                 padding: 6, radius: 20, communitySubTab: 1),

        .content(id: "community-prayer-tab", tab: 3,
                 message: "Share prayer requests and support others in the Prayer section.",
                 padding: 6, radius: 20, communitySubTab: 2),

        .content(id: "community-daily-tab", tab: 3,
                 message: "Answer the daily question and see how others responded.",
                 padding: 6, radius: 20, communitySubTab: 3),

        .content(id: "community-compose-button", tab: 3,
                 message: "Tap the pencil icon to post to the current section.",
                 edge: .bottom, padding: 8, radius: 50, communitySubTab: 0),

        // Library tab
        .tabSwitch(slot: 4, switchTo: 4,
                   message: "Finally, let's check your Library."),

        .content(id: "saved-bookmarks-tab", tab: 4,
                 message: "Your bookmarked verses are organized into collections here.",
                 padding: 6, radius: 4, savedSubTab: 0),

        .content(id: "saved-prayers-tab", tab: 4,
                 message: "Prayers you save from the Daily tab appear here.",
                 padding: 6, radius: 4, savedSubTab: 1),

        .content(id: "saved-devotionals-tab", tab: 4,
                 message: "Saved devotionals are stored here for easy access.",
                 padding: 6, radius: 4, savedSubTab: 2),

        .content(id: "saved-affirmations-tab", tab: 4,
                 message: "Your saved affirmations live here.",
                 padding: 6, radius: 4, savedSubTab: 3),

        // Done
        .completion,
    ]

    var currentStep: WalkthroughStep? {
        guard isActive, !showWelcomeCard, !isTransitioning, steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    var totalSteps: Int { steps.count }

    // MARK: Actions

    /// Starts the walkthrough once the reader content is loaded.
    /// Polls for the first step's coach mark frame before showing the overlay.
    func start() {
        currentStepIndex = 0
        appNav?.selectedTab = 0
        showWelcomeCard = true
        isActive = true
    }

    /// Called when the user taps "Let's take a tour" on the welcome card.
    func beginTour() {
        isTransitioning = true

        // Phase 1: Show white immediately (behind the welcome card)
        showWhiteFade = true

        // Phase 2: Fade out the welcome card — white is already behind it
        withAnimation(.easeIn(duration: 0.8)) {
            showWelcomeCard = false
        }

        // Phase 3: Hold on white, then fade it out to reveal the reader
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            withAnimation(.easeOut(duration: 1.0)) {
                self?.showWhiteFade = false
            }
        }

        // Phase 4: Fade in the first spotlight step
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            withAnimation(.easeOut(duration: 0.8)) {
                self?.isTransitioning = false
            }
        }
    }

    /// Called when the user taps "Skip" on the welcome card.
    func skipTour() {
        showWelcomeCard = false
        complete()
    }

    private func waitForReaderThenActivate() {
        // The coach mark frame for the first verse is reported only after
        // the Bible text loads. Poll briefly until it appears.
        if anchorFrames["reader-verse-row"] != nil {
            // Reader content is loaded — ready to begin spotlight steps.
            return
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
                if let subTab = nextStep.communitySubTab {
                    self?.appNav?.pendingCommunityTab = subTab
                }
                if let subTab = nextStep.savedSubTab {
                    self?.appNav?.pendingSavedTab = subTab
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                withAnimation(Self.stepAnimation) {
                    self?.isTransitioning = false
                }
            }
        } else {
            if let subTab = nextStep.communitySubTab {
                appNav?.pendingCommunityTab = subTab
            }
            if let subTab = nextStep.savedSubTab {
                appNav?.pendingSavedTab = subTab
            }
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
                if let subTab = prevStep.communitySubTab {
                    self?.appNav?.pendingCommunityTab = subTab
                }
                if let subTab = prevStep.savedSubTab {
                    self?.appNav?.pendingSavedTab = subTab
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                withAnimation(Self.stepAnimation) {
                    self?.isTransitioning = false
                }
            }
        } else {
            if let subTab = prevStep.communitySubTab {
                appNav?.pendingCommunityTab = subTab
            }
            if let subTab = prevStep.savedSubTab {
                appNav?.pendingSavedTab = subTab
            }
            withAnimation(Self.stepAnimation) {
                currentStepIndex = prevIndex
            }
        }
    }

    /// TODO: Remove — debug-only jump for fast step navigation during design.
    func jumpTo(step index: Int) {
        let clamped = min(max(index, 0), steps.count - 1)
        guard clamped != currentStepIndex else { return }

        let targetStep = steps[clamped]
        let targetTab = targetStep.switchToTab ?? (targetStep.targetTab >= 0 ? targetStep.targetTab : nil)

        // Switch tab if needed
        if let tab = targetTab, tab != appNav?.selectedTab {
            appNav?.selectedTab = tab
        }
        if let subTab = targetStep.communitySubTab {
            appNav?.pendingCommunityTab = subTab
        }
        if let subTab = targetStep.savedSubTab {
            appNav?.pendingSavedTab = subTab
        }

        withAnimation(Self.stepAnimation) {
            currentStepIndex = clamped
        }
    }

    func skip() {
        // Jump to the completion card instead of dismissing immediately
        if let completionIndex = steps.lastIndex(where: { $0.isCompletion }) {
            withAnimation(Self.stepAnimation) {
                currentStepIndex = completionIndex
            }
        } else {
            complete()
        }
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

    /// Tab label text for each slot index — must match ContentView's .tabItem labels.
    private static let tabLabels = ["Reader", "Daily", "Habits", "Community", "Library", "Profile"]

    /// Finds the actual tab bar button frame by searching for the UILabel with
    /// matching text in the UIKit view hierarchy. Works on both iPhone (bottom
    /// tab bar) and iPad (compact top tab bar) across all device sizes.
    func tabBarFrame(slot: Int, screenSize: CGSize, safeAreaTop: CGFloat, safeAreaBottom: CGFloat) -> CGRect {
        guard slot < Self.tabLabels.count,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return fallbackTabBarFrame(slot: slot, screenSize: screenSize, safeAreaTop: safeAreaTop, safeAreaBottom: safeAreaBottom)
        }

        let targetText = Self.tabLabels[slot]

        // Find the UILabel whose text matches the tab name
        if let label = Self.findLabel(withText: targetText, in: window) {
            // Walk up to the tappable button container (usually 1-2 levels up)
            let button = label.superview?.superview ?? label.superview ?? label
            let frame = button.convert(button.bounds, to: window)
            // Sanity check — frame should be in the top or bottom portion of the screen
            if frame.midY < screenSize.height * 0.15 || frame.midY > screenSize.height * 0.85 {
                return frame
            }
        }

        return fallbackTabBarFrame(slot: slot, screenSize: screenSize, safeAreaTop: safeAreaTop, safeAreaBottom: safeAreaBottom)
    }

    private static func findLabel(withText text: String, in view: UIView) -> UILabel? {
        if let label = view as? UILabel, label.text == text {
            return label
        }
        for sub in view.subviews {
            if let found = findLabel(withText: text, in: sub) {
                return found
            }
        }
        return nil
    }

    private func fallbackTabBarFrame(slot: Int, screenSize: CGSize, safeAreaTop: CGFloat, safeAreaBottom: CGFloat) -> CGRect {
        // Even distribution fallback — only used if UIKit introspection fails
        let tabCount: CGFloat = 6
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        if isIPad {
            let centerY: CGFloat = safeAreaTop > 40 ? safeAreaTop / 2 : 25
            let totalWidth: CGFloat = 500
            let slotWidth = totalWidth / tabCount
            let startX = (screenSize.width - totalWidth) / 2
            let centerX = startX + (CGFloat(slot) + 0.5) * slotWidth
            return CGRect(x: centerX - 40, y: centerY - 18, width: 80, height: 36)
        } else {
            let slotWidth = screenSize.width / tabCount
            let tabBarHeight: CGFloat = 49
            let centerX = (CGFloat(slot) + 0.5) * slotWidth
            let centerY = screenSize.height - safeAreaBottom - tabBarHeight / 2
            return CGRect(x: centerX - slotWidth * 0.4, y: centerY - 22.5, width: slotWidth * 0.8, height: 45)
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
