//
//  TouchTypeFilteredTapView.swift
//  ScriptureScribe
//
//  A transparent tap target that can tell a finger from an Apple Pencil.
//
//  SwiftUI has no way to filter a gesture by touch type, so controls that sit on
//  top of the drawing canvas use this instead of a plain Button. When
//  `passPencilThrough` is true (a drawing tool is selected), pencil touches are
//  refused in hitTest and fall through to the PKCanvasView underneath, so drawing
//  across the control still draws. Finger taps are always accepted, which is what
//  makes these controls usable without putting the pencil down.
//
//  Mirrors the touch-type filtering already used by PassThroughPKCanvasView.
//

import SwiftUI
import UIKit

struct TouchTypeFilteredTapView: UIViewRepresentable {

    var passPencilThrough: Bool
    var action: () -> Void

    final class TapView: UIView {
        var passPencilThrough = false

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            if passPencilThrough,
               let touches = event?.allTouches,
               touches.contains(where: { $0.type == .pencil }) {
                return nil      // let the pencil reach the canvas below
            }
            return super.hitTest(point, with: event)
        }
    }

    final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func handleTap() { action() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> TapView {
        let view = TapView()
        view.backgroundColor   = .clear
        view.passPencilThrough = passPencilThrough
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        // Both types are allowed here; whether a pencil ever arrives is decided
        // by hitTest above, so hand/lasso mode keeps working with the pencil.
        tap.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: TapView, context: Context) {
        uiView.passPencilThrough   = passPencilThrough
        context.coordinator.action = action
    }
}

// MARK: - Convenience

extension View {
    /// Makes this view tappable by finger at all times, while letting Apple Pencil
    /// touches fall through to whatever sits underneath when `passPencilThrough`
    /// is true. The view itself becomes non-hit-testable — it is purely visual.
    func fingerTappable(
        passPencilThrough: Bool,
        label: String,
        clipTo shape: some Shape = Rectangle(),
        action: @escaping () -> Void
    ) -> some View {
        self
            .allowsHitTesting(false)
            .overlay {
                TouchTypeFilteredTapView(passPencilThrough: passPencilThrough,
                                         action: action)
                    .clipShape(shape)
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityAction(.default, action)
    }
}
