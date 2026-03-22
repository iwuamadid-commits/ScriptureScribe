//
//  SubscriptionViewModel.swift
//  ScriptureScribe
//
//  Manages StoreKit 2 subscriptions and premium entitlement state.
//  Injected as an environment object from ScriptureScribeApp.
//

import Combine
import StoreKit
import SwiftUI

@MainActor
final class SubscriptionViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isPremium:         Bool           = false
    @Published var products:          [Product]      = []
    @Published var purchasedProductIDs: Set<String>  = []
    @Published var isLoading:         Bool           = false
    @Published var errorMessage:      String?        = nil
    @Published var showPaywall:       Bool           = false

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?
    private let premiumKey = "isPremiumCached"

    // MARK: - Init

    /// Set the signed-in user's ID so admins get automatic premium access.
    /// Also re-checks StoreKit entitlements when the user changes.
    func configureForUser(_ userId: String?) {
        if AdminManager.isAdmin(userId) {
            updatePremiumStatus(true)
        } else {
            // In DEBUG with scheme override, skip the StoreKit check
            // so the "-isPremiumCached YES" argument works for any account.
            #if DEBUG
            if UserDefaults.standard.bool(forKey: premiumKey) { return }
            #endif
            // Re-check actual StoreKit entitlement so premium doesn't
            // leak between accounts on the same device.
            Task { await checkEntitlement() }
        }
    }

    init() {
        // Restore cached premium status from UserDefaults.
        // In DEBUG: check "-isPremiumCached YES" in the scheme to force premium on.
        isPremium = UserDefaults.standard.bool(forKey: premiumKey)

        // Start listening for transaction updates
        transactionListener = listenForTransactions()

        // Load products and check entitlements (skip if debug override is active)
        Task {
            await loadProducts()
            #if DEBUG
            if !UserDefaults.standard.bool(forKey: premiumKey) {
                await checkEntitlement()
            }
            #else
            await checkEntitlement()
            #endif
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(
                for: SubscriptionProduct.allProductIds
            )
            // Sort: weekly, monthly, yearly, lifetime
            products = storeProducts.sorted { a, b in
                let order = SubscriptionProduct.allProductIds
                return (order.firstIndex(of: a.id) ?? 0) < (order.firstIndex(of: b.id) ?? 0)
            }
        } catch {
            print("[SubscriptionVM] Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                purchasedProductIDs.insert(transaction.productID)
                updatePremiumStatus(true)

            case .userCancelled:
                break

            case .pending:
                // Transaction requires approval (e.g. Ask to Buy)
                break

            @unknown default:
                break
            }
        } catch {
            errorMessage = error.userMessage
        }

        isLoading = false
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        isLoading = true
        do {
            try await AppStore.sync()
            await checkEntitlement()
        } catch {
            errorMessage = "Could not restore purchases. Please try again."
        }
        isLoading = false
    }

    // MARK: - Check Entitlement

    func checkEntitlement() async {
        // In DEBUG, never override the scheme argument "-isPremiumCached YES"
        #if DEBUG
        if UserDefaults.standard.bool(forKey: premiumKey) { return }
        #endif

        var activePurchases: Set<String> = []

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                activePurchases.insert(transaction.productID)
            } catch {
                print("[SubscriptionVM] Transaction verification failed: \(error.localizedDescription)")
            }
        }

        purchasedProductIDs = activePurchases
        let hasPremium = !activePurchases.isEmpty
        updatePremiumStatus(hasPremium)
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.checkEntitlement()
                }
            }
        }
    }

    // MARK: - Helpers

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    private func updatePremiumStatus(_ premium: Bool) {
        isPremium = premium
        UserDefaults.standard.set(premium, forKey: premiumKey)
    }

    /// Convenience: returns the Product for a given tier, if loaded.
    func product(for tier: SubscriptionProduct) -> Product? {
        products.first { $0.id == tier.rawValue }
    }

    /// Whether the yearly product offers a free trial.
    func hasFreeTrial(for product: Product) -> Bool {
        product.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }
}
