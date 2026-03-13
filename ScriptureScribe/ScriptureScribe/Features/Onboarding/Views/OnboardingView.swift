//
//  OnboardingView.swift
//  ScriptureScribe
//
//  A swipeable first-launch walkthrough that introduces the app's
//  key features. Shown once via an @AppStorage flag in ContentView.
//

import SwiftUI

// MARK: - Slide Data

private struct OnboardingSlide: Identifiable {
    let id = UUID()
    let symbol: String?   // SF Symbol name (nil for the welcome slide)
    let useLogo: Bool     // true → show WatermarkLogo instead of SF Symbol
    let headline: String
    let description: String
}

private let slides: [OnboardingSlide] = [
    OnboardingSlide(
        symbol: nil, useLogo: true,
        headline: "Welcome to\nScripture Scribe",
        description: "Your companion for reading, reflecting on, and living out God's Word every day."
    ),
    OnboardingSlide(
        symbol: "book.fill", useLogo: false,
        headline: "Your Bible, Your Way",
        description: "Read Scripture in multiple translations. Swipe between pages, zoom in, and listen with audio read-aloud."
    ),
    OnboardingSlide(
        symbol: "pencil.and.scribble", useLogo: false,
        headline: "Annotate & Draw",
        description: "Highlight verses, sketch notes with Apple Pencil, and add sticky notes right on the page."
    ),
    OnboardingSlide(
        symbol: "sun.max.fill", useLogo: false,
        headline: "Daily Devotional",
        description: "Start each day with a verse, prayer, affirmation, and guided reflection — all prepared for you."
    ),
    OnboardingSlide(
        symbol: "checkmark.circle.fill", useLogo: false,
        headline: "Build Faith Habits",
        description: "Track your spiritual habits, build streaks, and watch your consistency grow over time."
    ),
    OnboardingSlide(
        symbol: "person.2.fill", useLogo: false,
        headline: "Grow Together",
        description: "Share insights, prayers, and gratitude. Bookmark verses, save devotionals, and make it yours with 8 beautiful themes."
    ),
]

// MARK: - OnboardingView

struct OnboardingView: View {

    let onComplete: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var currentPage = 0

    private var theme: any AppTheme { themeManager.currentTheme }
    private var isLastPage: Bool { currentPage == slides.count - 1 }

    var body: some View {
        ZStack {
            // Full-screen background
            theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Paged slide carousel
                TabView(selection: $currentPage) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        SlideContentView(slide: slide, theme: theme, pageIndex: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Custom page dots
                HStack(spacing: 8) {
                    ForEach(0..<slides.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? Color(theme.primary) : Color(theme.primary).opacity(0.25))
                            .frame(width: 8, height: 8)
                            .scaleEffect(i == currentPage ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 24)

                // Bottom buttons
                bottomButtons
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Bottom Buttons

    @ViewBuilder
    private var bottomButtons: some View {
        if isLastPage {
            // "Get Started" — centered, large
            Button(action: onComplete) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(theme.primary))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: 340)
        } else {
            HStack {
                // Skip
                Button(action: onComplete) {
                    Text("Skip")
                        .font(.subheadline)
                        .foregroundStyle(Color(theme.textSecondary))
                }

                Spacer()

                // Next
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentPage += 1
                    }
                } label: {
                    Text("Next")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color(theme.primary))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Individual Slide

private struct SlideContentView: View {

    let slide: OnboardingSlide
    let theme: any AppTheme
    let pageIndex: Int

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Visual: logo or SF Symbol
            if slide.useLogo {
                Image("WatermarkLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .scaleEffect(appeared ? 1.0 : 0.6)
                    .opacity(appeared ? 1.0 : 0)
            } else if let symbol = slide.symbol {
                ZStack {
                    Circle()
                        .fill(Color(theme.primary).opacity(0.12))
                        .frame(width: 120, height: 120)

                    Image(systemName: symbol)
                        .font(.system(size: 50))
                        .foregroundStyle(Color(theme.primary))
                }
                .scaleEffect(appeared ? 1.0 : 0.6)
                .opacity(appeared ? 1.0 : 0)
            }

            // Headline
            Text(slide.headline)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(theme.text))
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 10)

            // Description
            Text(slide.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(theme.textSecondary))
                .padding(.horizontal, 32)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 10)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) {
                appeared = true
            }
        }
    }
}
