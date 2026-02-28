//
//  ZoomScrollView.swift
//  ScriptureScribe
//
//  A UIScrollView wrapper that gives native iOS pinch-to-zoom behaviour:
//    • Zoom anchors to the exact midpoint between the user's two fingers
//    • Pan with momentum and rubber-band bounce
//    • Double-tap to reset zoom to 1×
//    • When annotation mode is active (isScrollingDisabled = true), all
//      scroll and zoom gestures are disabled so PencilKit can draw freely.
//
//  Usage:
//      ZoomScrollView(minScale: 0.5, maxScale: 4.0, isScrollingDisabled: false) {
//          // your SwiftUI content here
//      }
//

import SwiftUI
import UIKit

// MARK: - Pencil Pass-Through Container

/// A container view that optionally blocks Apple Pencil touches from reaching
/// its children, letting them fall through to the parent UIScrollView for scrolling.
/// Finger touches always pass through to children so bookmarking still works.
private class PencilPassThroughView: UIView {
    var blockPencilTouches = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if blockPencilTouches,
           let touches = event?.allTouches, !touches.isEmpty,
           touches.allSatisfy({ $0.type == .pencil }) {
            return nil
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - ZoomScrollView

struct ZoomScrollView<Content: View>: UIViewRepresentable {

    let minScale:            CGFloat
    let maxScale:            CGFloat
    let isScrollingDisabled: Bool
    /// When false (hand tool), Apple Pencil touches are blocked from reaching
    /// content so they scroll instead. Finger touches still reach content for
    /// verse bookmarking via long-press.
    var isContentInteractive: Bool = true
    /// When set to a non-nil value, the scroll view animates to that Y offset and
    /// the binding is immediately cleared so it can be triggered again later.
    var scrollToOffset:      Binding<CGFloat?>? = nil
    /// Increment this integer to instantly snap to the top and reset zoom to 1×.
    /// Used when navigating to a new chapter without a specific verse target.
    var resetTrigger:        Int = 0
    /// Optional callback fired on double-tap. When provided and returning `true`,
    /// the zoom toggle is skipped — used for "double-tap to add note".
    var onDoubleTap:         (() -> Bool)? = nil
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        // ── ScrollView setup ────────────────────────────────────────────
        let scrollView = UIScrollView()
        scrollView.delegate                       = context.coordinator
        scrollView.minimumZoomScale               = minScale
        scrollView.maximumZoomScale               = maxScale
        scrollView.bouncesZoom                    = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator   = true
        scrollView.backgroundColor                = .clear
        scrollView.keyboardDismissMode            = .onDrag
        // Delay content touches so the scroll view can detect swipes first.
        // When scrolling is disabled (drawing mode) this is flipped to false
        // in updateUIView for responsive PencilKit drawing.
        scrollView.delaysContentTouches           = !isScrollingDisabled
        scrollView.canCancelContentTouches        = true

        // ── Pencil pass-through container ──────────────────────────────
        let container = PencilPassThroughView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(container)

        // ── Host the SwiftUI content tree ────────────────────────────────
        let hosting = UIHostingController(rootView: content())
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            // Container fills the scroll view's content area
            container.topAnchor     .constraint(equalTo: scrollView.topAnchor),
            container.bottomAnchor  .constraint(equalTo: scrollView.bottomAnchor),
            container.leadingAnchor .constraint(equalTo: scrollView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            container.widthAnchor   .constraint(equalTo: scrollView.widthAnchor),

            // Hosting view fills the container
            hosting.view.topAnchor     .constraint(equalTo: container.topAnchor),
            hosting.view.bottomAnchor  .constraint(equalTo: container.bottomAnchor),
            hosting.view.leadingAnchor .constraint(equalTo: container.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        context.coordinator.hosting    = hosting
        context.coordinator.container  = container
        context.coordinator.scrollView = scrollView

        // ── Double-tap to reset zoom ─────────────────────────────────────
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Flip scroll/zoom on/off for annotation mode
        scrollView.isScrollEnabled                   = !isScrollingDisabled
        scrollView.pinchGestureRecognizer?.isEnabled = !isScrollingDisabled
        // When scrolling is enabled, delay content touches so swipes scroll
        // instead of triggering verse long-press. When disabled (drawing mode),
        // deliver touches immediately for responsive PencilKit drawing.
        scrollView.delaysContentTouches              = !isScrollingDisabled

        // Allow Apple Pencil to scroll/zoom when scrolling is enabled (e.g. hand mode).
        // By default UIScrollView only responds to finger touches for scrolling.
        if !isScrollingDisabled {
            let allTypes: [NSNumber] = [
                NSNumber(value: UITouch.TouchType.direct.rawValue),
                NSNumber(value: UITouch.TouchType.pencil.rawValue),
                NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
            ]
            scrollView.panGestureRecognizer.allowedTouchTypes = allTypes
            scrollView.pinchGestureRecognizer?.allowedTouchTypes = allTypes
        }

        // When hand tool is active, block pencil touches from reaching content
        // so they go to the scroll view for scrolling. Finger touches still pass
        // through for verse bookmarking.
        context.coordinator.container?.blockPencilTouches = !isContentInteractive

        // Keep the double-tap callback in sync with the latest closure.
        context.coordinator.onDoubleTap = onDoubleTap

        // Push updated SwiftUI content to the hosted view
        context.coordinator.hosting?.rootView = content()

        // Chapter changed — snap to top and reset zoom to 1× instantly.
        // Happens while contentOpacity is 0, so the jump is invisible to the user.
        // Very long chapters (Psalm 119 = 176 verses, Numbers 7 = 89 verses) need
        // many run-loop passes for SwiftUI to compute their full layout inside the
        // hosting controller. A single DispatchQueue.main.async is not enough.
        // We fire staggered resets over 0.3 s; the content is invisible the whole time.
        if resetTrigger != context.coordinator.lastResetTrigger {
            context.coordinator.lastResetTrigger = resetTrigger
            context.coordinator.scheduleScrollReset(scrollView)
        }

        // Scroll to a requested Y offset (e.g. when navigating from Community to a verse).
        // Subtract 120 pt so the verse lands in the upper third of the screen rather than
        // at the very top — gives it breathing room and makes the highlight visible.
        if let binding = scrollToOffset, let targetY = binding.wrappedValue {
            let safeY = max(0, targetY - 120)
            // Use a longer, custom animation instead of the system's fast default
            // so the scroll glides smoothly to the target verse (about 1 second).
            UIView.animate(withDuration: 1.0, delay: 0, options: [.curveEaseInOut]) {
                scrollView.contentOffset = CGPoint(x: 0, y: safeY)
            }
            DispatchQueue.main.async { binding.wrappedValue = nil }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hosting:          UIHostingController<Content>?
        fileprivate var container: PencilPassThroughView?
        weak var scrollView:  UIScrollView?
        var lastResetTrigger: Int = 0
        var onDoubleTap:      (() -> Bool)?
        private var pendingResets: [DispatchWorkItem] = []

        /// Fires scroll-to-top resets at staggered intervals so at least one
        /// lands after SwiftUI finishes its layout pass. Content is invisible
        /// (contentOpacity = 0) during this window so there is no flicker.
        func scheduleScrollReset(_ scrollView: UIScrollView) {
            pendingResets.forEach { $0.cancel() }
            pendingResets.removeAll()
            for delay in [0.0, 0.05, 0.1, 0.15, 0.2, 0.3] {
                let item = DispatchWorkItem { [weak scrollView] in
                    guard let sv = scrollView else { return }
                    sv.setZoomScale(1.0, animated: false)
                    sv.setContentOffset(.zero, animated: false)
                }
                pendingResets.append(item)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            }
        }

        // Required by UIScrollViewDelegate — return the view to zoom
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            container
        }

        // Keep the zoomed content centred when smaller than the scroll view
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let content = container else { return }
            let offsetX = max((scrollView.bounds.width  - content.frame.width)  / 2, 0)
            let offsetY = max((scrollView.bounds.height - content.frame.height) / 2, 0)
            content.center = CGPoint(
                x: scrollView.contentSize.width  / 2 + offsetX,
                y: scrollView.contentSize.height / 2 + offsetY
            )
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            // If the caller handles the double-tap (e.g. for "add note"), skip zoom toggle.
            if let handler = onDoubleTap, handler() { return }
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom in 2× centred on the tap location
                let loc  = recognizer.location(in: container)
                let size = CGSize(
                    width:  scrollView.bounds.width  / 2,
                    height: scrollView.bounds.height / 2
                )
                let rect = CGRect(
                    x: loc.x - size.width  / 2,
                    y: loc.y - size.height / 2,
                    width:  size.width,
                    height: size.height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
