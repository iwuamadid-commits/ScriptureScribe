//
//  FeedView.swift
//  ScriptureScribe
//
//  The Community tab — 4 sections selectable via tabs across the top:
//    • Reflections  — scripture-linked posts + verse picker (existing)
//    • Gratitude    — text + optional photo
//    • Prayer       — prayer requests with 🙏 button and comments
//    • Daily        — open-ended question tied to today's devotion
//
//  Anyone can browse all sections. An account is required to post or reply.
//

import SwiftUI

// MARK: - Tab Enum

private enum CommunityTab: Int, CaseIterable, Identifiable {
    case reflections, gratitude, prayer, daily
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .reflections: return "Insights"
        case .gratitude:   return "Gratitude"
        case .prayer:      return "Prayer"
        case .daily:       return "Daily"
        }
    }
}

// MARK: - FeedView

struct FeedView: View {

    @EnvironmentObject var authVM:         AuthViewModel
    @EnvironmentObject var themeManager:   ThemeManager
    @EnvironmentObject var appNav:         AppNavigation
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel

    // ViewModels — one per section
    @StateObject private var communityVM  = CommunityViewModel()
    @StateObject private var gratitudeVM  = GratitudeViewModel()
    @StateObject private var prayerVM     = PrayerViewModel()
    @StateObject private var dailyVM      = DailyQuestionViewModel()

    // Sheet controls
    @State private var selectedTab:   CommunityTab = .reflections
    @State private var showAuth       = false
    @State private var showCreate     = false   // Reflections compose sheet
    @State private var showGratitude  = false   // Gratitude compose sheet
    @State private var showPrayer     = false   // Prayer compose sheet
    @State private var showPaywall    = false
    @State private var selectedPost:  Post?     = nil
    @State private var editingPost:   Post?     = nil   // opens edit sheet

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                themeManager.currentTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Section tabs ───────────────────────────────────
                    communityTabBar

                    // ── Content ────────────────────────────────────────
                    ZStack {
                        switch selectedTab {
                        case .reflections:
                            reflectionsContent

                        case .gratitude:
                            GratitudeFeedView(vm: gratitudeVM, isPremium: subscriptionVM.isPremium, onCompose: {
                                guard subscriptionVM.isPremium else { showPaywall = true; return }
                                if authVM.isSignedIn { showGratitude = true }
                                else                 { showAuth      = true }
                            }, onUpgrade: { showPaywall = true })

                        case .prayer:
                            PrayerFeedView(vm: prayerVM, isPremium: subscriptionVM.isPremium, onCompose: {
                                guard subscriptionVM.isPremium else { showPaywall = true; return }
                                if authVM.isSignedIn { showPrayer = true }
                                else                 { showAuth   = true }
                            }, onUpgrade: { showPaywall = true })

                        case .daily:
                            DailyQuestionView(vm: dailyVM, isPremium: subscriptionVM.isPremium, onUpgrade: { showPaywall = true })
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                }
            }
            .navigationTitle("Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        handleComposeAction()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20))
                            .foregroundStyle(themeManager.currentTheme.primary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    // Daily tab has no compose button — the "Share your answer" button
                    // lives inside DailyQuestionView itself.
                    .opacity(selectedTab == .daily ? 0 : 1)
                    .disabled(selectedTab == .daily)
                }
            }
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // ── Deep-link from Daily tab → Daily sub-tab ───────────────
            // onAppear: handles the case where Community tab was not yet visible
            // when pendingCommunityTab was set (tab just became active).
            .onAppear {
                guard let tab = appNav.pendingCommunityTab,
                      let communityTab = CommunityTab(rawValue: tab) else { return }
                selectedTab = communityTab
                appNav.pendingCommunityTab = nil
            }
            // onChange: handles the case where Community tab is already active
            // when the Daily tab button is tapped.
            .onChange(of: appNav.pendingCommunityTab) { _, tab in
                guard let tab, let communityTab = CommunityTab(rawValue: tab) else { return }
                withAnimation { selectedTab = communityTab }
                appNav.pendingCommunityTab = nil
            }
            // ── Sheets ─────────────────────────────────────────────────
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showAuth) { AuthView() }
            .sheet(isPresented: $showCreate) {
                if let user = authVM.currentUser {
                    CreatePostView(currentUser: user) { text, verseRef, verseText in
                        Task {
                            await communityVM.createPost(
                                userId:      user.id,
                                displayName: user.displayName,
                                photoURL:    user.photoURL,
                                text:        text,
                                verseRef:    verseRef,
                                verseText:   verseText
                            )
                        }
                    }
                }
            }
            .sheet(isPresented: $showGratitude) {
                if let user = authVM.currentUser {
                    CreateGratitudeView(currentUser: user) { text, imageData in
                        Task {
                            await gratitudeVM.createPost(
                                userId:      user.id,
                                displayName: user.displayName,
                                photoURL:    user.photoURL,
                                text:        text,
                                imageData:   imageData
                            )
                        }
                    }
                }
            }
            .sheet(isPresented: $showPrayer) {
                if let user = authVM.currentUser {
                    CreatePrayerView(currentUser: user) { text in
                        Task {
                            await prayerVM.createRequest(
                                userId:      user.id,
                                displayName: user.displayName,
                                photoURL:    user.photoURL,
                                text:        text
                            )
                        }
                    }
                }
            }
            .sheet(item: $selectedPost) { post in
                CommentsView(post: post, currentUser: authVM.currentUser)
            }
            .sheet(item: $editingPost) { post in
                EditTextSheet(title: "Edit Post", originalText: post.text) { newText in
                    Task { await communityVM.editPost(post, newText: newText) }
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var communityTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(CommunityTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.title)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab
                                ? themeManager.currentTheme.primary
                                : themeManager.currentTheme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(
                                selectedTab == tab
                                    ? themeManager.currentTheme.primary.opacity(0.12)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(themeManager.currentTheme.surface)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Section Header

    private func sectionHeader(icon: String, title: String, description: String) -> some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(themeManager.currentTheme.primary)
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
            Text(description)
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

    // MARK: - Reflections Content (existing behavior, untouched)

    private var reflectionsContent: some View {
        Group {
            if communityVM.isLoading && communityVM.posts.isEmpty {
                ProgressView("Loading…")
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if communityVM.posts.isEmpty {
                VStack(spacing: 16) {
                    sectionHeader(
                        icon:        "quote.bubble.fill",
                        title:       "Insights",
                        description: "Share what God is teaching you through Scripture. Tap the pencil icon to attach a verse and post your thoughts."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundStyle(themeManager.currentTheme.primary.opacity(0.4))
                    Text("No insights yet.\nBe the first to share!")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        if authVM.isSignedIn { showCreate = true }
                        else                 { showAuth   = true }
                    } label: {
                        Text("Share an Insight")
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
                    sectionHeader(
                        icon:        "quote.bubble.fill",
                        title:       "Insights",
                        description: "Share what God is teaching you through Scripture. Tap the pencil icon to attach a verse and post your thoughts."
                    )

                    // Sign-in nudge for guests — subtle, non-blocking
                    if !authVM.isSignedIn {
                        Button { showAuth = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus")
                                Text("Sign in to share your own insights")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(themeManager.currentTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(themeManager.currentTheme.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                        }
                    }

                    LazyVStack(spacing: 12) {
                        ForEach(Array(communityVM.posts.enumerated()), id: \.element.id) { index, post in
                            PostCardView(
                                post:          post,
                                currentUserId: authVM.currentUserID,
                                isLiked:       communityVM.likedPostIds.contains(post.id),
                                onLike: {
                                    if let uid = authVM.currentUserID {
                                        Task { await communityVM.toggleLike(post: post, userId: uid) }
                                    }
                                },
                                onEdit:   { editingPost = post },
                                onDelete: {
                                    Task { await communityVM.deletePost(post) }
                                },
                                onTap: { selectedPost = post }
                            )
                            .blur(radius: (!subscriptionVM.isPremium && index > 0) ? 6 : 0)
                            .allowsHitTesting(subscriptionVM.isPremium || index == 0)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if !subscriptionVM.isPremium {
                        premiumUpgradeBanner
                    }
                }
                .refreshable { }
            }
        }
        .onAppear    { communityVM.startListening(userId: authVM.currentUserID) }
        .onDisappear { communityVM.stopListening() }
    }

    // MARK: - Compose Action (routes to the right sheet for each tab)

    private func handleComposeAction() {
        guard subscriptionVM.isPremium else {
            showPaywall = true
            return
        }
        switch selectedTab {
        case .reflections:
            if authVM.isSignedIn { showCreate    = true }
            else                 { showAuth      = true }
        case .gratitude:
            if authVM.isSignedIn { showGratitude = true }
            else                 { showAuth      = true }
        case .prayer:
            if authVM.isSignedIn { showPrayer    = true }
            else                 { showAuth      = true }
        case .daily:
            break   // compose button is hidden on the Daily tab
        }
    }

    // MARK: - Premium Upgrade Banner (shown below blurred posts)

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

            Button {
                showPaywall = true
            } label: {
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
