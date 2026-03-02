//
//  PaywallView.swift
//  ScriptureScribe
//
//  Full-screen paywall sheet showing subscription tiers,
//  feature comparison, and purchase buttons.
//

import StoreKit
import SwiftUI

struct PaywallView: View {

    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    @EnvironmentObject var themeManager:   ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTier: SubscriptionProduct = .yearly

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // Header
                    headerSection

                    // Feature list
                    featureList

                    // Tier picker
                    tierPicker

                    // Subscribe button
                    subscribeButton

                    // Restore
                    Button {
                        Task { await subscriptionVM.restorePurchases() }
                    } label: {
                        Text("Restore Purchases")
                            .font(.footnote)
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    // Legal
                    Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period.")
                        .font(.caption2)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let error = subscriptionVM.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 24)
            }
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "F5C842"), Color(hex: "E87040")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Upgrade to Pro")
                .font(.title.weight(.bold))
                .foregroundStyle(themeManager.currentTheme.text)

            Text("Unlock everything Scripture Scribe has to offer")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow("Unlimited saved colors",           icon: "paintpalette.fill")
            featureRow("Unlimited bookmark collections",  icon: "folder.fill")
            featureRow("All Bible translations",          icon: "book.fill")
            featureRow("Save daily devotions & prayers",  icon: "heart.fill")
            featureRow("Full community access",           icon: "person.3.fill")
            featureRow("Audio Bible",                     icon: "headphones")
            featureRow("Watermark-free sharing",          icon: "square.and.arrow.up.fill")
            featureRow("Unlimited habits",                icon: "checkmark.circle.fill")
        }
        .padding(.horizontal, 24)
    }

    private func featureRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(themeManager.currentTheme.primary)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.text)
            Spacer()
        }
    }

    // MARK: - Tier Picker

    private var tierPicker: some View {
        VStack(spacing: 10) {
            ForEach(SubscriptionProduct.allCases, id: \.self) { tier in
                let product = subscriptionVM.product(for: tier)
                let isSelected = selectedTier == tier

                Button {
                    selectedTier = tier
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tier.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(themeManager.currentTheme.text)

                                if tier == .yearly {
                                    Text("Best Value")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(Color(hex: "F5C842"))
                                        )
                                        .foregroundStyle(.black)
                                }
                            }

                            if let product {
                                if tier == .yearly,
                                   subscriptionVM.hasFreeTrial(for: product) {
                                    Text("7-day free trial, then \(product.displayPrice)/year")
                                        .font(.caption)
                                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                                } else {
                                    Text(priceLabel(for: product, tier: tier))
                                        .font(.caption)
                                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected
                                             ? themeManager.currentTheme.primary
                                             : themeManager.currentTheme.textSecondary.opacity(0.4))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(themeManager.currentTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isSelected
                                            ? themeManager.currentTheme.primary
                                            : themeManager.currentTheme.border,
                                            lineWidth: isSelected ? 2 : 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func priceLabel(for product: Product, tier: SubscriptionProduct) -> String {
        switch tier {
        case .weekly:   return "\(product.displayPrice)/week"
        case .monthly:  return "\(product.displayPrice)/month"
        case .yearly:   return "\(product.displayPrice)/year"
        case .lifetime: return "\(product.displayPrice) one-time"
        }
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        Button {
            guard let product = subscriptionVM.product(for: selectedTier) else { return }
            Task { await subscriptionVM.purchase(product) }
        } label: {
            Group {
                if subscriptionVM.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    if selectedTier == .yearly,
                       let product = subscriptionVM.product(for: .yearly),
                       subscriptionVM.hasFreeTrial(for: product) {
                        Text("Start Free Trial")
                    } else {
                        Text("Subscribe Now")
                    }
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [themeManager.currentTheme.primary,
                                     themeManager.currentTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(subscriptionVM.isLoading)
        .padding(.horizontal, 20)
    }
}
