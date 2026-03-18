//
//  GratitudeFeedView.swift
//  ScriptureScribe
//
//  The Gratitude section inside the Community tab.
//  Users share text + optional photos of what they are grateful for today.
//

import SwiftUI

struct GratitudeFeedView: View {

    @EnvironmentObject var authVM:       AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager

    @ObservedObject var vm: GratitudeViewModel

    var isPremium: Bool = true
    let onCompose: () -> Void   // called by parent FeedView when the "+" button is tapped
    var onUpgrade: (() -> Void)? = nil

    @State private var selectedPost: GratitudePost? = nil   // opens comments sheet
    @State private var editingPost:  GratitudePost? = nil   // opens edit sheet

    // MARK: - Section Header

    private var sectionHeader: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.title3)
                    .foregroundStyle(Color.green)
                Text("Gratitude")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
            Text("Celebrate God's goodness. Share what you're grateful for today, big or small, and encourage others along the way.")
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
            if vm.isLoading && vm.posts.isEmpty {
                ProgressView("Loading…")
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if vm.posts.isEmpty {
                VStack(spacing: 16) {
                    sectionHeader
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "leaf")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.green.opacity(0.4))
                    Text("No gratitude posts yet.\nBe the first to share!")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(action: onCompose) {
                        Text("Share Your Gratitude")
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

                    if vm.isUploading {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Uploading photo…")
                                .font(.caption)
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    LazyVStack(spacing: 12) {
                        ForEach(vm.posts) { post in
                            GratitudeCardView(
                                post:          post,
                                currentUserId: authVM.currentUserID,
                                isLiked:       vm.likedGratitudeIds.contains(post.id),
                                onLike: {
                                    if let uid = authVM.currentUserID {
                                        Task { await vm.toggleLike(post: post, userId: uid) }
                                    }
                                },
                                onEdit:    { editingPost = post },
                                onComment: { selectedPost = post },
                                onDelete:  { Task { await vm.deletePost(post) } },
                                onReport:  {
                                    if let uid = authVM.currentUserID {
                                        Task { await vm.reportPost(id: post.id, userId: uid) }
                                    }
                                }
                            )
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .sheet(item: $selectedPost) { post in
                    GratitudeCommentsView(post: post, currentUser: authVM.currentUser)
                }
                .sheet(item: $editingPost) { post in
                    if AdminManager.isAdmin(authVM.currentUserID) {
                        AdminEditTextSheet(title: "Edit Gratitude Post", originalText: post.text, originalDisplayName: post.displayName) { text, displayName in
                            Task { await vm.adminEditPost(post, text: text, displayName: displayName) }
                        }
                    } else {
                        EditTextSheet(title: "Edit Post", originalText: post.text) { newText in
                            Task { await vm.editPost(post, newText: newText) }
                        }
                    }
                }

            } else {
                // ── Free: one preview post (no interaction) + upgrade banner pinned at bottom ──
                VStack(spacing: 0) {
                    sectionHeader

                    if let firstPost = vm.posts.first {
                        GratitudeCardView(
                            post:          firstPost,
                            currentUserId: authVM.currentUserID,
                            isLiked:       false,
                            onLike:        { },
                            onEdit:        { },
                            onComment:     { },
                            onDelete:      { },
                            onReport:      { }
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
