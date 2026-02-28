//
//  StreakToolbarButton.swift
//  ScriptureScribe
//
//  A compact 🔥 N chip intended for placement as a trailing ToolbarItem in any
//  NavigationStack. Tapping it presents StreakDetailView as a sheet.
//
//  Usage (inside a .toolbar block):
//      ToolbarItem(placement: .topBarTrailing) { StreakToolbarButton() }
//

import SwiftUI

struct StreakToolbarButton: View {

    @EnvironmentObject var streakVM: StreakViewModel
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 3) {
                Text("🔥")
                    .font(.subheadline)
                Text("\(max(streakVM.currentStreak, 1))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .sheet(isPresented: $showDetail) {
            StreakDetailView()
                .environmentObject(streakVM)
        }
        .accessibilityLabel("\(max(streakVM.currentStreak, 1)) day streak. Tap for details.")
    }
}
