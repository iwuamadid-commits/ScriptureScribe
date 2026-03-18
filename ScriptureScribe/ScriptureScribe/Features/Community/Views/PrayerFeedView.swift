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

            } else if isPremium {
                // ── Premium: full scrollable feed ────────────────────────
                ScrollView {
                    sectionHeader

                    LazyVStack(spacing: 12) {
                        ForEach(vm.requests) { request in
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
                                onDelete:  { Task { await vm.deleteRequest(request) } },
                                onReport:  {
                                    if let uid = authVM.currentUserID {
                                        Task { await vm.reportRequest(id: request.id, userId: uid) }
                                    }
                                }
                            )
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .sheet(item: $selectedRequest) { req in
                    PrayerCommentsView(request: req, currentUser: authVM.currentUser)
                }
                .sheet(item: $editingRequest) { req in
                    if AdminManager.isAdmin(authVM.currentUserID) {
                        AdminEditTextSheet(title: "Edit Prayer Request", originalText: req.text, originalDisplayName: req.displayName) { text, displayName in
                            Task { await vm.adminEditRequest(req, text: text, displayName: displayName) }
                        }
                    } else {
                        EditTextSheet(title: "Edit Prayer Request", originalText: req.text) { newText in
                            Task { await vm.editRequest(req, newText: newText) }
                        }
                    }
                }

            } else {
                // ── Free: one preview post (no interaction) + upgrade banner pinned at bottom ──
                VStack(spacing: 0) {
                    sectionHeader

                    if let firstRequest = vm.requests.first {
                        PrayerCardView(
                            request:     firstRequest,
                            currentUser: authVM.currentUser,
                            isPraying:   false,
                            onPray:      { },
                            onEdit:      { },
                            onComment:   { },
                            onDelete:    { },
                            onReport:    { }
                        )
                        .allowsHitTesting(false)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    Spacer()

                    premiumUpgradeBanner
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear    { vm.startListening(userId: authVM.currentUserID) }
        .onDisappear { vm.stopListening() }
    }

    // MARK: - Premium Upgrade Banner

    private var premiumUpgradeBanner: some View {
        VStack(spacing: 12) {
            Text("Unlock Full Community")
                .font(.headline)
                .foregroundStyle(themeManager.currentTheme.text)
            Text("See all posts, comment, like, and share your own.")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button { onUpgrade?() } label: {
                HStack(spacing: 8) {
                    ProBadge()
                    Text("Upgrade to Pro")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.80, blue: 0.22),
                                 Color(red: 0.97, green: 0.58, blue: 0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
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
