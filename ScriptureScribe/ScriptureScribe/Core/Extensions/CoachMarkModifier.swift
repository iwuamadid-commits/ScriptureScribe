//
//  CoachMarkModifier.swift
//  ScriptureScribe
//
//  A preference key and convenience modifier for the interactive walkthrough.
//  Any view that needs to be spotlighted attaches `.coachMark("some-id")`.
//  The frame is reported in the "walkthrough" named coordinate space set on
//  the root container in ContentView.
//

import SwiftUI

// MARK: - Preference Key

struct CoachMarkFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect],
                       nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - View Modifier

extension View {
    /// Tags this view as a walkthrough spotlight target.
    /// The frame is only reported when the walkthrough is active.
    func coachMark(_ id: String, active: Bool = true) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: CoachMarkFrameKey.self,
                        value: active ? [id: geo.frame(in: .named("walkthrough"))] : [:]
                    )
            }
        )
    }
}
