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
//  Access:
//    • No account — a "Join the Community" screen in each section. Community posts
//      can only be read by signed-in users (see firestore.rules), so the feeds aren't
//      loaded at all; loading them would just fail with a permission error.
//    • Free account — a preview of each section plus an upgrade banner.
//    • Pro — everything.
//

import SwiftUI

// MARK: - Auth Sheet Mode

/// Which way the sign-in sheet opens from the guest screen.
private enum AuthSheetMode: String, Identifiable {
    case signIn, signUp
    var id: String { rawValue }
}

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

    @EnvironmentObject var authVM:              AuthViewModel
    @EnvironmentObject var themeManager:        ThemeManager
    @EnvironmentObject var appNav:              AppNavigation
    @EnvironmentObject var subscriptionVM:      SubscriptionViewModel
    @EnvironmentObject var walkthroughManager:  WalkthroughManager

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
    @State private var showErrorAlert = false
    @State private var errorAlertMessage = ""
    @State private var authSheetMode: AuthSheetMode? = nil   // sign-in sheet from the guest screen

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                themeManager.currentTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Section tabs ───────────────────────────────────
                    communityTabBar

                    // ── Content ────────────────────────────────────────
                    ZStack {
                        if authVM.isSignedIn {
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
                        } else if authVM.isRestoringSession {
                            // Signed in, but the profile is still loading at launch
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            guestContent(for: selectedTab)
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
                            .coachMark("community-compose-button")
                            .contentShape(Rectangle())
                    }
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
            .sheet(item: $authSheetMode) { mode in
                AuthView(startsInSignUp: mode == .signUp)
            }
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
                if AdminManager.isAdmin(authVM.currentUserID) {
                    AdminEditPostSheet(post: post) { text, verseRef, verseText, displayName in
                        Task { await communityVM.adminEditPost(post, text: text, verseRef: verseRef, verseText: verseText, displayName: displayName) }
                    }
                } else {
                    EditTextSheet(title: "Edit Post", originalText: post.text) { newText in
                        Task { await communityVM.editPost(post, newText: newText) }
                    }
                }
            }
            .alert("Something went wrong", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorAlertMessage)
            }
            .onChange(of: communityVM.errorMessage) { _, msg in
                guard let msg, !walkthroughManager.isActive else { communityVM.errorMessage = nil; return }
                errorAlertMessage = msg; showErrorAlert = true; communityVM.errorMessage = nil
            }
            .onChange(of: gratitudeVM.errorMessage) { _, msg in
                guard let msg, !walkthroughManager.isActive else { gratitudeVM.errorMessage = nil; return }
                errorAlertMessage = msg; showErrorAlert = true; gratitudeVM.errorMessage = nil
            }
            .onChange(of: prayerVM.errorMessage) { _, msg in
                guard let msg, !walkthroughManager.isActive else { prayerVM.errorMessage = nil; return }
                errorAlertMessage = msg; showErrorAlert = true; prayerVM.errorMessage = nil
            }
            .onChange(of: dailyVM.errorMessage) { _, msg in
                guard let msg, !walkthroughManager.isActive else { dailyVM.errorMessage = nil; return }
                errorAlertMessage = msg; showErrorAlert = true; dailyVM.errorMessage = nil
            }
            .onChange(of: authVM.isSignedIn) { _, signedIn in
                if !signedIn {
                    communityVM.stopListening()
                    gratitudeVM.stopListening()
                    prayerVM.stopListening()
                    dailyVM.stopListening()
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
                            .coachMark("community-insights-tab", active: tab == .reflections)
                            .coachMark("community-gratitude-tab", active: tab == .gratitude)
                            .coachMark("community-prayer-tab", active: tab == .prayer)
                            .coachMark("community-daily-tab", active: tab == .daily)
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

    private func sectionHeader(icon: String, title: String, description: String,
                               iconColor: Color? = nil) -> some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor ?? themeManager.currentTheme.primary)
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

            } else if subscriptionVM.isPremium {
                // ── Premium: full scrollable feed ────────────────────────
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
                        ForEach(communityVM.posts) { post in
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
                                onDelete: { Task { await communityVM.deletePost(post) } },
                                onTap:    { selectedPost = post },
                                onReport: {
                                    if let uid = authVM.currentUserID {
                                        Task { await communityVM.reportPost(id: post.id, userId: uid) }
                                    }
                                }
                            )
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .refreshable { }

            } else {
                // ── Free: one preview post (no interaction) + upgrade banner pinned at bottom ──
                VStack(spacing: 0) {
                    sectionHeader(
                        icon:        "quote.bubble.fill",
                        title:       "Insights",
                        description: "Share what God is teaching you through Scripture."
                    )

                    if let firstPost = communityVM.posts.first {
                        PostCardView(
                            post:          firstPost,
                            currentUserId: authVM.currentUserID,
                            isLiked:       false,
                            onLike:        { },
                            onEdit:        { },
                            onDelete:      { },
                            onTap:         { },
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
        .onAppear    { communityVM.startListening(userId: authVM.currentUserID) }
        .onDisappear { communityVM.stopListening() }
    }

    // MARK: - Guest Content (no account)

    /// What someone without an account sees in each section: the section's heading,
    /// a blurred post-shaped placeholder (no real or made-up content), and an
    /// invitation to create a free account.
    private func guestContent(for tab: CommunityTab) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                switch tab {
                case .reflections:
                    sectionHeader(
                        icon:        "quote.bubble.fill",
                        title:       "Insights",
                        description: "Share what God is teaching you through Scripture."
                    )
                case .gratitude:
                    sectionHeader(
                        icon:        "leaf.fill",
                        title:       "Gratitude",
                        description: "Celebrate God's goodness. Share what you're grateful for today, big or small, and encourage others along the way.",
                        iconColor:   .green
                    )
                case .prayer:
                    sectionHeader(
                        icon:        "hands.sparkles.fill",
                        title:       "Prayer Requests",
                        description: "Share what's on your heart and let the community stand with you."
                    )
                case .daily:
                    sectionHeader(
                        icon:        "sparkles",
                        title:       "Daily Question",
                        description: "A new question tied to today's devotion. Share your answer and see how others are hearing from God."
                    )
                }

                placeholderPostCard
                    .padding(.horizontal, 16)

                joinCommunityCard
            }
            .padding(.bottom, 24)
        }
    }

    /// A blurred card shaped like a post, so the section doesn't look empty.
    private var placeholderPostCard: some View {
        let theme = themeManager.currentTheme
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(theme.border)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(theme.border).frame(width: 110, height: 10)
                    Capsule().fill(theme.border.opacity(0.7)).frame(width: 70, height: 8)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(theme.border).frame(height: 10)
                Capsule().fill(theme.border).frame(height: 10)
                Capsule().fill(theme.border).frame(width: 180, height: 10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(theme.border.opacity(0.5), lineWidth: 1)
        )
        .blur(radius: 2)
        .accessibilityHidden(true)
    }

    private var joinCommunityCard: some View {
        let theme = themeManager.currentTheme
        return VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.title2)
                .foregroundStyle(theme.primary)

            Text("Join the Community")
                .font(.headline)
                .foregroundStyle(theme.text)

            // Pro is tied to the Apple ID, so someone can have Pro without an account.
            Text(subscriptionVM.isPremium
                 ? "Create a free account or sign in to see every post and share your own with Pro."
                 : "Create a free account to preview what other believers are sharing. Upgrade to Pro anytime to see every post and share your own.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Button {
                authSheetMode = .signUp
            } label: {
                Text("Create a Free Account")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button {
                authSheetMode = .signIn
            } label: {
                Text("Already have an account? Sign In")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.primary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(theme.border.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Compose Action (routes to the right sheet for each tab)

    private func handleComposeAction() {
        // Posting needs an account before anything else, so guests are asked to
        // create one (or sign in) rather than being shown the paywall.
        guard authVM.isSignedIn else {
            if !authVM.isRestoringSession { authSheetMode = .signUp }
            return
        }
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

            Button {
                showPaywall = true
            } label: {
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
