//
//  StreakBadgeView.swift
//  ScriptureScribe
//
//  A small badge showing the user's current reading streak.
//  Displayed as a flame emoji with the streak count (e.g. 🔥 7).
//  Always visible — StreakViewModel always reports at least 1 after first launch.
//

import SwiftUI

struct StreakBadgeView: View {

    let streak: Int

    var body: some View {
        HStack(spacing: 2) {
            Text("🔥")
                .font(.subheadline)
            Text("\(max(streak, 1))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .accessibilityLabel("\(max(streak, 1)) day streak")
    }
}
