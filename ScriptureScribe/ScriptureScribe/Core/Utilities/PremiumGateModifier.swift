//
//  PremiumGateModifier.swift
//  ScriptureScribe
//
//  Reusable view modifier that shows a lock overlay and opens
//  the paywall when a free user taps a premium-only feature.
//

import SwiftUI

struct PremiumGateModifier: ViewModifier {

    let isPremium: Bool
    @Binding var showPaywall: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if !isPremium {
                    Color.black.opacity(0.01) // invisible tap target
                        .onTapGesture { showPaywall = true }
                }
            }
            .overlay(alignment: .topTrailing) {
                if !isPremium {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .padding(4)
                }
            }
    }
}

extension View {
    /// Overlays a lock icon and intercepts taps for free users.
    func premiumGate(isPremium: Bool, showPaywall: Binding<Bool>) -> some View {
        modifier(PremiumGateModifier(isPremium: isPremium, showPaywall: showPaywall))
    }
}
