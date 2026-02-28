//
//  TranslationBrowserView.swift
//  ScriptureScribe
//
//  A searchable sheet that shows all available Bible translations (1,500+).
//  English translations are listed first. The user taps one to switch.
//

import SwiftUI

struct TranslationBrowserView: View {

    @ObservedObject var vm: ReaderViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText  = ""
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoadingTranslations {
                    ProgressView("Loading translations…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // English section pinned to top
                        let english = filtered.filter { $0.isEnglish }
                        if !english.isEmpty {
                            Section("English") {
                                ForEach(english) { translation in
                                    let isLocked = !subscriptionVM.isPremium
                                        && !PremiumLimits.freeBibleIds.contains(translation.id)
                                    TranslationRow(
                                        translation: translation,
                                        isSelected: vm.selectedTranslation?.id == translation.id,
                                        isLocked: isLocked
                                    )
                                    .onTapGesture {
                                        if isLocked {
                                            showPaywall = true
                                        } else {
                                            Task { await vm.selectTranslation(translation) }
                                        }
                                    }
                                }
                            }
                        }

                        // All other languages, grouped
                        let others = filtered.filter { !$0.isEnglish }
                        let grouped = Dictionary(grouping: others) { $0.language.name }
                        ForEach(grouped.keys.sorted(), id: \.self) { language in
                            Section(language) {
                                ForEach(grouped[language] ?? []) { translation in
                                    let isLocked = !subscriptionVM.isPremium
                                        && !PremiumLimits.freeBibleIds.contains(translation.id)
                                    TranslationRow(
                                        translation: translation,
                                        isSelected: vm.selectedTranslation?.id == translation.id,
                                        isLocked: isLocked
                                    )
                                    .onTapGesture {
                                        if isLocked {
                                            showPaywall = true
                                        } else {
                                            Task { await vm.selectTranslation(translation) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .searchable(text: $searchText, prompt: "Search by name, abbreviation, or language")
            .navigationTitle("Choose Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    /// Filters the full translation list based on what the user typed in the search bar.
    private var filtered: [BibleTranslation] {
        guard !searchText.isEmpty else { return vm.translations }
        let q = searchText.lowercased()
        return vm.translations.filter {
            $0.name.lowercased().contains(q)
            || $0.abbreviation.lowercased().contains(q)
            || $0.language.name.lowercased().contains(q)
            || $0.nameLocal.lowercased().contains(q)
        }
    }
}

// MARK: - Single Translation Row

private struct TranslationRow: View {

    let translation: BibleTranslation
    let isSelected:  Bool
    var isLocked:    Bool = false

    var body: some View {
        HStack {
            // Abbreviation chip (e.g. "KJV", "NIV")
            Text(translation.abbreviation)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(translation.name)
                    .font(.body)
                    .foregroundStyle(isLocked ? .secondary : .primary)
                Text(translation.language.nameLocal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            } else if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle()) // makes the whole row tappable
    }
}
