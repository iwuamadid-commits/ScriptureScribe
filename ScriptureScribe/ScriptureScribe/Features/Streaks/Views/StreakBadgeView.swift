//
//  StreakBadgeView.swift
//  ScriptureScribe
//
//  A small badge showing the user's current reading streak.
//  Displayed as a flame emoji with the streak count (e.g. 🔥 7).
//  Disappears when the streak is 0 (first launch before any streak is recorded).
//

import SwiftUI

struct StreakBadgeView: View {

    let streak: Int

    var body: some View {
        if streak > 0 {
            HStack(spacing: 2) {
                Text("🔥")
                    .font(.subheadline)
                Text("\(streak)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .accessibilityLabel("\(streak) day streak")
        }
    }
}
