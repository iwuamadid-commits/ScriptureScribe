//
//  PrayerFeedView.swift
//  ScriptureScribe
//
//  The Prayer Requests section inside the Community tab.
//

import SwiftUI

struct PrayerFeedView: View {

    @EnvironmentObject var authVM:       AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager

    @ObservedObject var vm: PrayerViewModel

    var isPremium: Bool = true
    let onCompose:  () -> Void
    var onUpgrade: (() -> Void)? = nil
    @State private var selectedRequest: PrayerRequest? = nil
    @State private var editingRequest:  PrayerRequest? = nil

    // MARK: - Section Header

    private var sectionHeader: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "hands.sparkles.fill")
                    .font(.title3)
                    .foregroundStyle(themeManager.currentTheme.primary)
                Text("Prayer Requests")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
            Text("Share what's on your heart and let the community stand with you. Tap 🙏 on any post to let someone know you're praying for them.")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.requests.isEmpty {
                ProgressView("Loading…")
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if vm.requests.isEmpty {
                VStack(spacing: 16) {
                    sectionHeader
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("🙏")
                        .font(.system(size: 48))
                    Text("No prayer requests yet.\nShare something the community can pray for.")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(action: onCompose) {
                        Text("Share a Prayer Request")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(themeManager.currentTheme.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                ScrollView {
                    sectionHeader

                    LazyVStack(spacing: 12) {
                        ForEach(Array(vm.requests.enumerated()), id: \.element.id) { index, request in
                            PrayerCardView(
                                request:     request,
                                currentUser: authVM.currentUser,
                                isPraying:   vm.prayingIds.contains(request.id),
                                onPray: {
                                    if let uid = authVM.currentUserID {
                                        Task { await vm.togglePraying(request: request, userId: uid) }
                                    }
                                },
                                onEdit:    { editingRequest = request },
                                onComment: { selectedRequest = request },
                                onDelete:  { Task { await vm.deleteRequest(request) } }
                            )
                            .blur(radius: (!isPremium && index > 0) ? 6 : 0)
                            .allowsHitTesting(isPremium || index == 0)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if !isPremium {
                        premiumUpgradeBanner
                    }
                }
                .sheet(item: $selectedRequest) { req in
                    PrayerCommentsView(request: req, currentUser: authVM.currentUser)
                }
                .sheet(item: $editingRequest) { req in
                    EditTextSheet(title: "Edit Prayer Request", originalText: req.text) { newText in
                        Task { await vm.editRequest(req, newText: newText) }
                    }
                }
            }
        }
        .onAppear    { vm.startListening(userId: authVM.currentUserID) }
        .onDisappear { vm.stopListening() }
    }

    // MARK: - Premium Upgrade Banner

    private var premiumUpgradeBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(themeManager.currentTheme.primary)
            Text("Unlock Full Community")
                .font(.headline)
                .foregroundStyle(themeManager.currentTheme.text)
            Text("Upgrade to Premium to see all posts, comment, like, and share your own.")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button { onUpgrade?() } label: {
                Text("Go Premium")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 160, minHeight: 44)
                    .background(Capsule().fill(themeManager.currentTheme.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(themeManager.currentTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(themeManager.currentTheme.border.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}
