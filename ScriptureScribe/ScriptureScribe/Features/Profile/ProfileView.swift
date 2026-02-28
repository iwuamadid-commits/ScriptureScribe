//
//  ProfileView.swift
//  ScriptureScribe
//
//  Settings & profile screen.
//  Phase 5: Theme picker, font prefs.
//  Phase 6: Auth, user info, community posts.
//

import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {

    @EnvironmentObject var themeManager:   ThemeManager
    @EnvironmentObject var authVM:        AuthViewModel
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    @State private var showThemePicker = false
    @State private var showAuth        = false
    @State private var showPaywall     = false
    @State private var photoPickerItem: PhotosPickerItem? = nil

    // Read streak values written by StreakViewModel in the Reader tab
    @AppStorage("streak_currentCount") private var currentStreak: Int = 0
    @AppStorage("streak_longestCount") private var longestStreak: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background
                    .ignoresSafeArea()

                List {

                    // ── Reading Streak ───────────────────────────────────────
                    Section {
                        HStack(spacing: 0) {
                            // Current streak
                            VStack(spacing: 6) {
                                HStack(spacing: 4) {
                                    Text("🔥")
                                        .font(.title2)
                                    Text("\(max(currentStreak, 0))")
                                        .font(.title.weight(.bold))
                                        .foregroundStyle(.orange)
                                }
                                Text("Current Streak")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)

                            Divider()
                                .frame(height: 44)

                            // Longest streak
                            VStack(spacing: 6) {
                                HStack(spacing: 4) {
                                    Text("🏆")
                                        .font(.title2)
                                    Text("\(max(longestStreak, 0))")
                                        .font(.title.weight(.bold))
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                }
                                Text("Best Streak")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Reading Streak")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    } footer: {
                        Text("Open the Reader tab each day to keep your streak alive.")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .listRowBackground(themeManager.currentTheme.surface)

                    // ── Subscription ────────────────────────────────────────
                    Section {
                        if subscriptionVM.isPremium {
                            HStack(spacing: 12) {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(.yellow)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Premium")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(themeManager.currentTheme.text)
                                    Text("All features unlocked")
                                        .font(.caption)
                                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                                }
                                Spacer()
                            }

                            Button {
                                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "gear")
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                        .frame(width: 24)
                                    Text("Manage Subscription")
                                        .foregroundStyle(themeManager.currentTheme.text)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                                        .font(.caption)
                                }
                            }
                        } else {
                            Button { showPaywall = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(.yellow)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Free Plan")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(themeManager.currentTheme.text)
                                        Text("Upgrade to unlock all features")
                                            .font(.caption)
                                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    }
                                    Spacer()
                                    Text("Upgrade")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule().fill(themeManager.currentTheme.primary)
                                        )
                                }
                            }
                        }

                        Button {
                            Task { await subscriptionVM.restorePurchases() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(themeManager.currentTheme.primary)
                                    .frame(width: 24)
                                Text("Restore Purchases")
                                    .foregroundStyle(themeManager.currentTheme.text)
                            }
                        }
                    } header: {
                        Text("Subscription")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .listRowBackground(themeManager.currentTheme.surface)

                    // ── Theme ────────────────────────────────────────────────
                    Section {
                        Button {
                            showThemePicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "paintpalette.fill")
                                    .foregroundStyle(themeManager.currentTheme.primary)
                                    .frame(width: 24)
                                Text("Theme")
                                    .foregroundStyle(themeManager.currentTheme.text)
                                Spacer()
                                Text(themeManager.currentTheme.name)
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .font(.subheadline)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .font(.caption)
                            }
                        }
                    } header: {
                        Text("Appearance")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .listRowBackground(themeManager.currentTheme.surface)

                    // ── Account ───────────────────────────────────────────────
                    Section {
                        if authVM.isSignedIn, let user = authVM.currentUser {
                            // Signed-in: show name, email, and tappable profile photo
                            HStack(spacing: 12) {
                                // Profile photo — tap to change
                                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                                    ZStack(alignment: .bottomTrailing) {
                                        avatarView(for: user, size: 52)
                                        // Small camera badge to hint it's tappable
                                        Image(systemName: "camera.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(themeManager.currentTheme.primary)
                                            .background(Circle().fill(themeManager.currentTheme.surface).padding(1))
                                    }
                                }
                                .onChange(of: photoPickerItem) { _, item in
                                    Task {
                                        guard let data = try? await item?.loadTransferable(type: Data.self),
                                              let uiImage = UIImage(data: data),
                                              let jpeg = uiImage.jpegData(compressionQuality: 0.8)
                                        else { return }
                                        await authVM.uploadAndSetProfilePhoto(imageData: jpeg)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(themeManager.currentTheme.text)
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    Text("Tap photo to change")
                                        .font(.caption2)
                                        .foregroundStyle(themeManager.currentTheme.textSecondary.opacity(0.6))
                                }
                            }
                            .padding(.vertical, 4)

                            // Sign Out button
                            Button(role: .destructive) {
                                authVM.signOut()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .foregroundStyle(.red)
                                        .frame(width: 24)
                                    Text("Sign Out")
                                        .foregroundStyle(.red)
                                }
                            }
                        } else {
                            // Signed-out: show sign-in prompt
                            Button {
                                showAuth = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.circle.fill")
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Sign In")
                                            .foregroundStyle(themeManager.currentTheme.text)
                                        Text("Join the community and back up your data")
                                            .font(.caption)
                                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                                        .font(.caption)
                                }
                            }
                        }
                    } header: {
                        Text("Account")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .listRowBackground(themeManager.currentTheme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showThemePicker) {
                ThemePickerView()
            }
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - Avatar helper

    /// Shows the user's photo if available, otherwise shows their initial in a circle.
    @ViewBuilder
    private func avatarView(for user: AppUser, size: CGFloat) -> some View {
        if let urlString = user.photoURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    // While loading or on error, fall back to the letter
                    Text(user.displayName.prefix(1).uppercased())
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(themeManager.currentTheme.border, lineWidth: 1))
        } else {
            Circle()
                .fill(themeManager.currentTheme.primary.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text(user.displayName.prefix(1).uppercased())
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(themeManager.currentTheme.primary)
                )
        }
    }
}

// MARK: - Theme Picker

struct ThemePickerView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ThemeManager.allThemes, id: \.name) { theme in
                            themeCard(theme)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Choose Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
        }
    }

    @ViewBuilder
    private func themeCard(_ theme: any AppTheme) -> some View {
        let isSelected = themeManager.currentTheme.name == theme.name

        Button {
            themeManager.setTheme(theme)
        } label: {
            VStack(spacing: 0) {

                // Preview: background + text + accent swatches
                ZStack {
                    theme.background
                    VStack(spacing: 6) {
                        // Fake lines representing Bible text
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.text.opacity(0.4))
                                .frame(height: 4)
                        }

                        // Accent swatch
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.primary)
                            .frame(height: 8)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(height: 80)

                // Theme name
                HStack {
                    Text(theme.name)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(themeManager.currentTheme.text)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(themeManager.currentTheme.primary)
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(themeManager.currentTheme.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? themeManager.currentTheme.primary
                            : themeManager.currentTheme.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.1 : 0.04), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView()
        .environmentObject(ThemeManager())
        .environmentObject(AuthViewModel())
}
