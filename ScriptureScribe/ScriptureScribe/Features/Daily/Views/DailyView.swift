//
//  DailyView.swift
//  ScriptureScribe
//
//  The Daily tab — verse, affirmation, prayer, devotion, and reflection questions.
//
//  At the top: a 7-day week strip + "View Calendar" link for browsing past days.
//  Verse card: tappable — navigates to that verse in the Reader with a gold highlight.
//  Affirmation card: faith-based daily affirmation with heart save.
//  Prayer + Devotion cards: heart button to save/unsave to Firebase.
//  Reflection card: questions + a button to jump to the Community Daily Question.
//
//  Section order is customizable — tap the toolbar button to rearrange.
//  Order persists in AppStorage across sessions.
//

import SwiftUI

// MARK: - Section Ordering

enum DailySection: String, CaseIterable, Codable, Identifiable {
    case verse, affirmation, prayer, devotion, reflection
    var id: String { rawValue }

    var label: String {
        switch self {
        case .verse:       return "Verse"
        case .affirmation: return "Affirmation"
        case .prayer:      return "Prayer"
        case .devotion:    return "Devotion"
        case .reflection:  return "Reflection"
        }
    }

    var icon: String {
        switch self {
        case .verse:       return "book.pages"
        case .affirmation: return "sparkles"
        case .prayer:      return "hands.clap.fill"
        case .devotion:    return "book.fill"
        case .reflection:  return "lightbulb.fill"
        }
    }
}

// MARK: - Image Composer Payload

/// Bundles the content to share as an image. Using fullScreenCover(item:) instead of
/// isPresented + separate state vars ensures the text is always fresh when the composer opens.
private struct ImageComposerPayload: Identifiable {
    let id        = UUID()
    let text:      String
    let reference: String
}

// MARK: - DailyView

struct DailyView: View {

    @StateObject  private var vm           = DailyViewModel()
    @EnvironmentObject var themeManager:   ThemeManager
    @EnvironmentObject var appNav:         AppNavigation
    @EnvironmentObject var authVM:         AuthViewModel
    @EnvironmentObject var savedVM:        SavedDevotionalsViewModel
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    @EnvironmentObject var walkthroughManager: WalkthroughManager

    @State private var showCalendar = false
    @State private var showAuth     = false
    @State private var showPaywall  = false
    @State private var showPrayerHeartAnim      = false
    @State private var showDevotionHeartAnim    = false
    @State private var showAffirmationHeartAnim = false
    @State private var imageComposerPayload: ImageComposerPayload? = nil
    @State private var editableSections: [DailySection] = DailySection.allCases
    @State private var draggedSectionID: String?
    @State private var sectionDragOffset: CGFloat = 0
    @State private var sectionSizes: [String: CGFloat] = [:]
    @State private var sectionSourceIndex: Int = 0

    // MARK: - Section Order (persisted)

    @AppStorage("dailySectionOrder") private var sectionOrderData: String = ""

    private var sectionOrder: [DailySection] {
        guard !sectionOrderData.isEmpty,
              let data = sectionOrderData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([DailySection].self, from: data),
              Set(decoded) == Set(DailySection.allCases)
        else {
            return DailySection.allCases
        }
        return decoded
    }

    private func saveSectionOrder(_ order: [DailySection]) {
        if let data = try? JSONEncoder().encode(order),
           let str = String(data: data, encoding: .utf8) {
            sectionOrderData = str
        }
    }

    // Formatted string for whichever date is selected
    private func dateString(_ date: Date) -> String {
        let f        = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Fixed calendar bar (outside ScrollView so swipe works) ──
                VStack(spacing: 0) {
                    WeekStripView(
                        selectedDate: vm.selectedDate,
                        onSelectDate: { date in
                            vm.selectedDate = date
                            Task { await vm.loadContent(for: date) }
                        },
                        isPremium: subscriptionVM.isPremium || AdminManager.isAdmin(authVM.currentUserID)
                    )

                    // "View Calendar" link — right-aligned below the week strip
                    HStack {
                        Spacer()
                        Button {
                            showCalendar = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                Text("View Calendar")
                                    .font(.caption.weight(.medium))
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .foregroundStyle(themeManager.currentTheme.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    Divider()
                }
                .background(themeManager.currentTheme.surface)

                // ── Scrollable content area ──────────────────────────────────
                ZStack {
                    themeManager.currentTheme.background
                        .ignoresSafeArea()

                    if vm.isLoading {
                        loadingView

                    } else if vm.isGenerating {
                        generatingView

                    } else if let message = vm.errorMessage {
                        errorView(message: message)

                    } else if let entry = vm.entry {
                        ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {

                                // ── Date header ──────────────────────────────────
                                Text(dateString(vm.selectedDate).uppercased())
                                .font(.caption.weight(.semibold))
                                .tracking(1.5)
                                .foregroundStyle(themeManager.currentTheme.primary)
                                .padding(.horizontal, 20)
                                .padding(.top, 4)
                                .padding(.bottom, 8)

                                // ── Sections in custom order (long-press to reorder) ───
                                ForEach(editableSections) { section in
                                    let isDragged = draggedSectionID == section.rawValue

                                    VStack(spacing: 0) {
                                        sectionView(for: section, entry: entry)
                                    }
                                    .background(
                                        GeometryReader { g in
                                            Color.clear.preference(
                                                key: SectionSizeKey.self,
                                                value: [section.rawValue: g.size.height]
                                            )
                                        }
                                    )
                                    // Insertion indicator line
                                    .overlay(alignment: .top) {
                                        if !isDragged, draggedSectionID != nil,
                                           sectionShowsTopIndicator(section) {
                                            Capsule()
                                                .fill(themeManager.currentTheme.primary.opacity(0.5))
                                                .frame(height: 3)
                                                .padding(.horizontal, 36)
                                                .offset(y: -4)
                                        }
                                    }
                                    .overlay(alignment: .bottom) {
                                        if !isDragged, draggedSectionID != nil,
                                           sectionShowsBottomIndicator(section) {
                                            Capsule()
                                                .fill(themeManager.currentTheme.primary.opacity(0.5))
                                                .frame(height: 3)
                                                .padding(.horizontal, 36)
                                                .offset(y: 4)
                                        }
                                    }
                                    .zIndex(isDragged ? 1 : 0)
                                    .offset(y: isDragged
                                            ? sectionDragOffset
                                            : sectionDisplacement(for: section))
                                    .scaleEffect(isDragged ? 1.02 : 1.0)
                                    .shadow(
                                        color: isDragged ? .black.opacity(0.15) : .clear,
                                        radius: 8, x: 0, y: 4
                                    )
                                    .animation(.spring(response: 0.45, dampingFraction: 0.82),
                                               value: sectionDisplacement(for: section))
                                    .animation(.spring(response: 0.3, dampingFraction: 0.8),
                                               value: draggedSectionID)
                                    .id("daily-\(section.rawValue)")
                                    // Long press — scroll-friendly view modifier
                                    .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                                        if !pressing, draggedSectionID == section.rawValue,
                                           sectionDragOffset == 0 {
                                            // Lifted without dragging — cancel
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                draggedSectionID = nil
                                            }
                                        }
                                    }) {
                                        sectionSourceIndex = editableSections.firstIndex(of: section) ?? 0
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            draggedSectionID = section.rawValue
                                        }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                    // Drag — inert (minimumDistance 10000) until this section is being dragged
                                    .simultaneousGesture(
                                        DragGesture(minimumDistance: isDragged ? 0 : 10000)
                                            .onChanged { drag in
                                                guard isDragged else { return }
                                                sectionDragOffset = drag.translation.height
                                            }
                                            .onEnded { _ in
                                                guard draggedSectionID != nil else { return }
                                                let proposed = proposedSectionIndex()
                                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                                    if proposed != sectionSourceIndex {
                                                        editableSections.move(
                                                            fromOffsets: IndexSet(integer: sectionSourceIndex),
                                                            toOffset: proposed > sectionSourceIndex ? proposed + 1 : proposed
                                                        )
                                                    }
                                                    sectionDragOffset = 0
                                                    draggedSectionID = nil
                                                }
                                            }
                                    )
                                }
                                .onPreferenceChange(SectionSizeKey.self) { sizes in
                                    sectionSizes.merge(sizes) { $1 }
                                }

                                Spacer().frame(height: 32)
                            }
                        }
                        .scrollDisabled(draggedSectionID != nil)
                        // Scroll to the relevant section when walkthrough step changes
                        .onChange(of: walkthroughManager.currentStepIndex) { _, _ in
                            scrollToWalkthroughSection(proxy: scrollProxy)
                        }
                        // Also scroll after a tab-switch transition completes (e.g. going back)
                        .onChange(of: walkthroughManager.isTransitioning) { _, transitioning in
                            if !transitioning {
                                scrollToWalkthroughSection(proxy: scrollProxy)
                            }
                        }
                        } // closes ScrollViewReader
                    }
                }   // closes ZStack (content area)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }       // closes outer VStack
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .navigationTitle("Daily")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showCalendar) {
                CalendarSheetView(selectedDate: vm.selectedDate) { date in
                    // Free (non-admin) users can only view today — show paywall for any other date
                    let hasFullAccess = subscriptionVM.isPremium || AdminManager.isAdmin(authVM.currentUserID)
                    if !hasFullAccess && !Calendar.current.isDateInToday(date) {
                        showCalendar = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            showPaywall = true
                        }
                        return
                    }
                    vm.selectedDate = date
                    Task { await vm.loadContent(for: date) }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showAuth) {
                AuthView()
            }
            .fullScreenCover(item: $imageComposerPayload) { payload in
                VerseImageComposerView(
                    verseText:      payload.text,
                    verseReference: payload.reference
                )
            }
        }
        .onAppear {
            editableSections = sectionOrder
        }
        .onChange(of: editableSections) { _, newSections in
            saveSectionOrder(newSections)
        }
        .task {
            await vm.load()
        }
        .task(id: authVM.currentUserID) {
            if let uid = authVM.currentUserID {
                await savedVM.load(userId: uid)
            }
        }
        // Navigate from Library → Daily: parse the pending date and load that day's content
        .onChange(of: appNav.pendingDailyDate) { _, dateString in
            guard let dateString, !dateString.isEmpty else { return }
            appNav.pendingDailyDate = nil
            // Free users can only view today
            guard subscriptionVM.isPremium else { return }
            let iso        = DateFormatter()
            iso.dateFormat = "yyyy-MM-dd"
            iso.locale     = Locale(identifier: "en_US_POSIX")
            if let date = iso.date(from: dateString) {
                vm.selectedDate = date
                Task { await vm.loadContent(for: date) }
            }
        }
    }

    // MARK: - Section Router

    private func scrollToWalkthroughSection(proxy: ScrollViewProxy) {
        guard let step = walkthroughManager.currentStep else { return }
        let sectionMap: [String: String] = [
            "daily-verse-section": "daily-verse",
            "daily-affirmation-section": "daily-affirmation",
            "daily-prayer-section": "daily-prayer",
            "daily-devotion-section": "daily-devotion",
            "daily-reflection-section": "daily-reflection"
        ]
        if let scrollID = sectionMap[step.id] {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(scrollID, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func sectionView(for section: DailySection, entry: DailyEntry) -> some View {
        switch section {
        case .verse:
            verseSection(entry: entry)
        case .affirmation:
            if !entry.affirmation.isEmpty {
                affirmationSection(entry: entry)
            }
        case .prayer:
            prayerSection(entry: entry)
        case .devotion:
            devotionSection(entry: entry)
        case .reflection:
            reflectionSection(entry: entry)
        }
    }

    // MARK: - Verse Section

    @ViewBuilder
    private func verseSection(entry: DailyEntry) -> some View {
        VStack(spacing: 0) {
            verseCard(entry: entry)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard draggedSectionID == nil else { return }
                    navigateToVerse(entry: entry)
                }

            HStack(spacing: 4) {
                Image(systemName: "book.pages")
                    .font(.caption2)
                Text("Tap to read in your Bible")
                    .font(.caption)
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundStyle(themeManager.currentTheme.textSecondary)
            .padding(.top, 6)
        }
        .coachMark("daily-verse-section")
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Affirmation Section

    @ViewBuilder
    private func affirmationSection(entry: DailyEntry) -> some View {
        sectionCard(
            icon:     "sparkles",
            title:    "Affirmation",
            body:     entry.affirmation,
            saveType: "affirmation",
            entry:    entry
        )
        .coachMark("daily-affirmation-section")
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard let uid = authVM.currentUserID else {
                showAuth = true
                return
            }
            if !savedVM.isSaved(type: "affirmation", entryDate: entry.date) {
                Task {
                    await savedVM.save(
                        type: "affirmation",
                        verseReference: entry.verseReference,
                        content: entry.affirmation,
                        entryDate: entry.date,
                        userId: uid
                    )
                }
            }
            showAffirmationHeartAnim = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showAffirmationHeartAnim = false
            }
        }
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 45))
                .foregroundStyle(Color.red.opacity(0.85))
                .scaleEffect(showAffirmationHeartAnim ? 1.0 : 0.3)
                .opacity(showAffirmationHeartAnim ? 1.0 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showAffirmationHeartAnim)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Prayer Section

    @ViewBuilder
    private func prayerSection(entry: DailyEntry) -> some View {
        sectionCard(
            icon:     "hands.clap.fill",
            title:    "Prayer",
            body:     entry.prayer,
            saveType: "prayer",
            entry:    entry
        )
        .coachMark("daily-prayer-section")
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard let uid = authVM.currentUserID else {
                showAuth = true
                return
            }
            if !savedVM.isSaved(type: "prayer", entryDate: entry.date) {
                Task {
                    await savedVM.save(
                        type: "prayer",
                        verseReference: entry.verseReference,
                        content: entry.prayer,
                        entryDate: entry.date,
                        userId: uid
                    )
                }
            }
            showPrayerHeartAnim = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showPrayerHeartAnim = false
            }
        }
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 45))
                .foregroundStyle(Color.red.opacity(0.85))
                .scaleEffect(showPrayerHeartAnim ? 1.0 : 0.3)
                .opacity(showPrayerHeartAnim ? 1.0 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showPrayerHeartAnim)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Devotion Section

    @ViewBuilder
    private func devotionSection(entry: DailyEntry) -> some View {
        sectionCard(
            icon:     "book.fill",
            title:    "Devotion",
            body:     entry.devotion,
            saveType: "devotional",
            entry:    entry
        )
        .coachMark("daily-devotion-section")
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard let uid = authVM.currentUserID else {
                showAuth = true
                return
            }
            if !savedVM.isSaved(type: "devotional", entryDate: entry.date) {
                Task {
                    await savedVM.save(
                        type: "devotional",
                        verseReference: entry.verseReference,
                        content: entry.devotion,
                        entryDate: entry.date,
                        userId: uid
                    )
                }
            }
            showDevotionHeartAnim = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showDevotionHeartAnim = false
            }
        }
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 45))
                .foregroundStyle(Color.red.opacity(0.85))
                .scaleEffect(showDevotionHeartAnim ? 1.0 : 0.3)
                .opacity(showDevotionHeartAnim ? 1.0 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showDevotionHeartAnim)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Reflection Section

    @ViewBuilder
    private func reflectionSection(entry: DailyEntry) -> some View {
        reflectionCard(entry: entry)
            .coachMark("daily-reflection-section")
            .padding(.horizontal, 20)
            .padding(.top, 16)
    }

    // MARK: - Loading States

    private var loadingView: some View {
        ProgressView()
            .tint(themeManager.currentTheme.primary)
    }

    private var generatingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(themeManager.currentTheme.primary)
            Text("Crafting today\u{2019}s devotional\u{2026}")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await vm.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(themeManager.currentTheme.primary)
        }
    }

    // MARK: - Navigate to verse in Reader

    private func navigateToVerse(entry: DailyEntry) {
        let parts     = entry.verseId.components(separatedBy: ".")
        guard parts.count >= 2 else { return }
        let chapterId = parts.prefix(2).joined(separator: ".")
        let verseNum  = parts.last ?? ""
        appNav.pendingVerseNumber = verseNum
        appNav.pendingChapterId   = chapterId
        appNav.selectedTab        = 0
    }

    // MARK: - Heart Button

    @ViewBuilder
    private func heartButton(type: String, entry: DailyEntry) -> some View {
        let isSaved = savedVM.isSaved(type: type, entryDate: entry.date)
        Button {
            guard let uid = authVM.currentUserID else {
                showAuth = true
                return
            }
            Task {
                if isSaved {
                    await savedVM.delete(type: type, entryDate: entry.date, userId: uid)
                } else {
                    let content: String = {
                        switch type {
                        case "prayer":      return entry.prayer
                        case "affirmation": return entry.affirmation
                        default:            return entry.devotion
                        }
                    }()
                    await savedVM.save(
                        type:           type,
                        verseReference: entry.verseReference,
                        content:        content,
                        entryDate:      entry.date,
                        userId:         uid
                    )
                }
            }
        } label: {
            Image(systemName: isSaved ? "heart.fill" : "heart")
                .foregroundStyle(isSaved ? .red : themeManager.currentTheme.textSecondary)
                .font(.body)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSaved)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }

    // MARK: - Verse Card

    @ViewBuilder
    private func verseCard(entry: DailyEntry) -> some View {
        let verseShareText: String = {
            let link = "scripturescribe://daily/\(entry.date)"
            if let text = vm.verseText, !text.isEmpty {
                return "\(entry.verseReference)\n\n\"\(text)\"\n\nShared from Scripture Scribe\n\n\(link)"
            }
            return "\(entry.verseReference)\n\nShared from Scripture Scribe\n\n\(link)"
        }()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.verseReference)
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(themeManager.currentTheme.primary)
                Spacer()
                if let text = vm.verseText, !text.isEmpty {
                    Button {
                        imageComposerPayload = ImageComposerPayload(
                            text:      text,
                            reference: entry.verseReference
                        )
                    } label: {
                        Image(systemName: "photo")
                            .font(.body)
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ShareLink(item: verseShareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let text = vm.verseText, !text.isEmpty {
                Text("\u{201C}\(text)\u{201D}")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(themeManager.currentTheme.text)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Open the Reader tab and choose a Bible translation to see the full verse text.")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.currentTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.currentTheme.primary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Section Card (Prayer / Devotion / Affirmation)

    @ViewBuilder
    private func sectionCard(
        icon:     String,
        title:    String,
        body:     String,
        saveType: String,
        entry:    DailyEntry
    ) -> some View {
        let sectionShareText: String = {
            let link = "scripturescribe://daily/\(entry.date)"
            let limit = 200
            if body.count <= limit {
                return "Today's \(title) from Scripture Scribe:\n\n\(body)\n\n\(link)"
            }
            // Truncate at the last word boundary so words aren't split
            let trimmed = String(body.prefix(limit))
            let preview = trimmed.last == " " ? String(trimmed.dropLast()) :
                          (trimmed.lastIndex(of: " ").map { String(trimmed[..<$0]) } ?? trimmed)
            return "Today's \(title) from Scripture Scribe:\n\n\(preview)...\n\nRead more in Scripture Scribe:\n\(link)"
        }()

        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.currentTheme.text)
                Spacer()
                heartButton(type: saveType, entry: entry)
                Button {
                    imageComposerPayload = ImageComposerPayload(
                        text:      body,
                        reference: "\(title) · \(entry.verseReference)"
                    )
                } label: {
                    Image(systemName: "photo")
                        .font(.body)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ShareLink(item: sectionShareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(body)
                .font(.body)
                .foregroundStyle(themeManager.currentTheme.text)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.currentTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.currentTheme.border.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
    }

    // MARK: - Reflection Questions Card

    @ViewBuilder
    private func reflectionCard(entry: DailyEntry) -> some View {
        let reflectionShareText: String = {
            let link = "scripturescribe://daily/\(entry.date)"
            if let q = entry.reflectionQuestions.first {
                return "Reflection Question:\n\n\(q)\n\nShared from Scripture Scribe\n\n\(link)"
            }
            return "Reflection from Scripture Scribe\n\n\(link)"
        }()

        VStack(alignment: .leading, spacing: 16) {

            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .font(.subheadline)
                Text("Reflect")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.currentTheme.text)
                Spacer()
                ShareLink(item: reflectionShareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let question = entry.reflectionQuestions.first {
                Text(question)
                    .font(.body)
                    .foregroundStyle(themeManager.currentTheme.text)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .padding(.vertical, 2)

            Button {
                appNav.pendingCommunityTab = 3
                appNav.selectedTab         = 3
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline)
                    Text("Share Your Reflection in Community")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(themeManager.currentTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.currentTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.currentTheme.border.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
    }

    // MARK: - Section Drag Helpers

    /// Target index based on drag distance, using actual measured section heights.
    private func proposedSectionIndex() -> Int {
        var offset = sectionDragOffset
        var proposed = sectionSourceIndex

        if offset > 0 {
            while proposed < editableSections.count - 1 {
                let nextID = editableSections[proposed + 1].rawValue
                let nextHeight = sectionSizes[nextID] ?? 300
                if offset > nextHeight * 0.5 {
                    offset -= nextHeight
                    proposed += 1
                } else {
                    break
                }
            }
        } else if offset < 0 {
            while proposed > 0 {
                let prevID = editableSections[proposed - 1].rawValue
                let prevHeight = sectionSizes[prevID] ?? 300
                if -offset > prevHeight * 0.5 {
                    offset += prevHeight
                    proposed -= 1
                } else {
                    break
                }
            }
        }

        return proposed
    }

    /// Items between source and target shift by the dragged section's
    /// full height, opening a clear gap at the insertion point.
    private func sectionDisplacement(for section: DailySection) -> CGFloat {
        guard let draggedID = draggedSectionID else { return 0 }
        guard section.rawValue != draggedID else { return 0 }
        guard let itemIndex = editableSections.firstIndex(of: section) else { return 0 }

        let proposed = proposedSectionIndex()
        let draggedHeight = sectionSizes[draggedID] ?? 300

        if sectionSourceIndex < proposed {
            // Dragging down — items between source and target shift up
            if itemIndex > sectionSourceIndex && itemIndex <= proposed {
                return -draggedHeight
            }
        } else if sectionSourceIndex > proposed {
            // Dragging up — items between target and source shift down
            if itemIndex >= proposed && itemIndex < sectionSourceIndex {
                return draggedHeight
            }
        }
        return 0
    }

    /// Whether a section should show the accent insertion line at its top edge.
    private func sectionShowsTopIndicator(_ section: DailySection) -> Bool {
        guard draggedSectionID != nil else { return false }
        let proposed = proposedSectionIndex()
        guard sectionSourceIndex > proposed else { return false }
        return editableSections.firstIndex(of: section) == proposed
    }

    /// Whether a section should show the accent insertion line at its bottom edge.
    private func sectionShowsBottomIndicator(_ section: DailySection) -> Bool {
        guard draggedSectionID != nil else { return false }
        let proposed = proposedSectionIndex()
        guard sectionSourceIndex < proposed else { return false }
        return editableSections.firstIndex(of: section) == proposed
    }
}

// MARK: - Preference Key for Section Sizes

private struct SectionSizeKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

#Preview {
    DailyView()
        .environmentObject(ThemeManager())
        .environmentObject(AppNavigation())
        .environmentObject(AuthViewModel())
        .environmentObject(SavedDevotionalsViewModel())
}
