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

struct ZoomScrollView<Content: View>: UIViewRepresentable {

    let minScale:           CGFloat
    let maxScale:           CGFloat
    let isScrollingDisabled: Bool
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

        // ── Host the SwiftUI content tree ────────────────────────────────
        let hosting = UIHostingController(rootView: content())
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor    .constraint(equalTo: scrollView.topAnchor),
            hosting.view.bottomAnchor .constraint(equalTo: scrollView.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            // Pin width to the scrollView frame so text wraps correctly
            hosting.view.widthAnchor  .constraint(equalTo: scrollView.widthAnchor),
        ])

        context.coordinator.hosting    = hosting
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
        scrollView.isScrollEnabled              = !isScrollingDisabled
        scrollView.pinchGestureRecognizer?.isEnabled = !isScrollingDisabled

        // Push updated SwiftUI content to the hosted view
        context.coordinator.hosting?.rootView = content()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hosting:    UIHostingController<Content>?
        weak var scrollView: UIScrollView?

        // Required by UIScrollViewDelegate — return the view to zoom
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hosting?.view
        }

        // Keep the zoomed content centred when smaller than the scroll view
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let content = hosting?.view else { return }
            let offsetX = max((scrollView.bounds.width  - content.frame.width)  / 2, 0)
            let offsetY = max((scrollView.bounds.height - content.frame.height) / 2, 0)
            content.center = CGPoint(
                x: scrollView.contentSize.width  / 2 + offsetX,
                y: scrollView.contentSize.height / 2 + offsetY
            )
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom in 2× centred on the tap location
                let loc  = recognizer.location(in: hosting?.view)
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
