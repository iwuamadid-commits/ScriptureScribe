//
//  TranslationBrowserView.swift
//  ScriptureScribe
//
//  Two-panel Bible version selector (inspired by the YouVersion Bible app):
//
//  • Main panel  → "My Versions" — user's saved translations, swipe-left to remove.
//                  "More Versions" row navigates to the full list.
//  • More panel  → Searchable, language-filterable list of all 1,500+ translations.
//
//  KJV is automatically added to My Versions on first launch (via ReaderViewModel).
//

import SwiftUI

struct TranslationBrowserView: View {

    @ObservedObject var vm: ReaderViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoadingTranslations {
                    ProgressView("Loading translations…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {

                        // MARK: My Versions
                        if !vm.myVersions.isEmpty {
                            Section("My Versions") {
                                ForEach(vm.myVersions) { translation in
                                    let isFree   = PremiumLimits.freeBibleIds.contains(translation.id)
                                    let isLocked = !subscriptionVM.isPremium && !isFree
                                    TranslationRow(
                                        translation:   translation,
                                        isSelected:    vm.selectedTranslation?.id == translation.id,
                                        isLocked:      isLocked,
                                        isFreeVersion: !subscriptionVM.isPremium && isFree
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isLocked {
                                            showPaywall = true
                                        } else {
                                            Task { await vm.selectTranslation(translation) }
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            vm.removeFromMyVersions(translation)
                                        } label: {
                                            Label("Remove", systemImage: "minus.circle")
                                        }
                                    }
                                }
                            }
                        }

                        // MARK: More Versions
                        Section {
                            NavigationLink {
                                MoreVersionsView(vm: vm, subscriptionVM: subscriptionVM)
                            } label: {
                                Label("More Versions", systemImage: "books.vertical")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Bible")
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
}

// MARK: - More Versions (full searchable, filterable list)

private struct MoreVersionsView: View {

    @ObservedObject var vm: ReaderViewModel
    @ObservedObject var subscriptionVM: SubscriptionViewModel

    @State private var searchText        = ""
    @State private var selectedLanguage: String? = nil
    @State private var showPaywall       = false

    /// Capitalizes the first letter of a language name so "español" and "Español"
    /// are treated as the same group across all grouping, filtering, and display.
    private func langName(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    var body: some View {
        Group {
            if vm.isLoadingTranslations {
                ProgressView("Loading translations…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Search bar — embedded as first row so it scrolls naturally with the list
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search versions...", text: $searchText)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Empty state — no results for the current search
                    if filteredList.isEmpty && !searchText.isEmpty {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No results for \"\(searchText)\"")
                                    .font(.body.weight(.medium))
                                Text("Sorry, we couldn't find a Bible version matching your search.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                    }

                    if selectedLanguage == nil {
                        // English pinned to top — free versions sorted first within the section
                        let english = filteredList.filter { $0.isEnglish }
                            .sorted {
                                let lFree = PremiumLimits.freeBibleIds.contains($0.id)
                                let rFree = PremiumLimits.freeBibleIds.contains($1.id)
                                return lFree && !rFree
                            }
                        if !english.isEmpty {
                            Section {
                                ForEach(english) { t in translationRow(t) }
                            } header: {
                                languageFilterHeader
                            }
                        }
                        // All other languages, plain grouped headers — native name as section title
                        let others  = filteredList.filter { !$0.isEnglish }
                        let grouped = Dictionary(grouping: others) { langName($0.language.nameLocal) }
                        ForEach(grouped.keys.sorted(), id: \.self) { lang in
                            Section(lang) {
                                ForEach(grouped[lang] ?? []) { t in translationRow(t) }
                            }
                        }
                    } else {
                        // Language filter active — header shows selected language as filter
                        let grouped = Dictionary(grouping: filteredList) { langName($0.language.nameLocal) }
                        ForEach(grouped.keys.sorted(), id: \.self) { lang in
                            Section {
                                ForEach(grouped[lang] ?? []) { t in translationRow(t) }
                            } header: {
                                languageFilterHeader
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("More Versions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func translationRow(_ translation: BibleTranslation) -> some View {
        let isFree   = PremiumLimits.freeBibleIds.contains(translation.id)
        let isLocked = !subscriptionVM.isPremium && !isFree
        TranslationRow(
            translation:   translation,
            isSelected:    vm.selectedTranslation?.id == translation.id,
            isLocked:      isLocked,
            isFreeVersion: !subscriptionVM.isPremium && isFree
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isLocked {
                showPaywall = true
            } else {
                Task { await vm.selectTranslation(translation) }
            }
        }
    }

    // MARK: - Language Filter Header (inline, replaces plain section title)

    private var languageFilterHeader: some View {
        Menu {
            Button {
                selectedLanguage = nil
            } label: {
                if selectedLanguage == nil {
                    Label("All Languages", systemImage: "checkmark")
                } else {
                    Text("All Languages")
                }
            }
            Divider()
            ForEach(availableLanguages, id: \.self) { language in
                Button {
                    selectedLanguage = language
                } label: {
                    if selectedLanguage == language {
                        Label(language, systemImage: "checkmark")
                    } else {
                        Text(language)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedLanguage ?? "English")  // "English" is already its own native name
                    .font(.footnote.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .textCase(nil)
        }
    }

    // MARK: - Filtering

    private var filteredList: [BibleTranslation] {
        var list = vm.translations

        // Language filter (keyed by native language name)
        if let lang = selectedLanguage {
            list = list.filter { langName($0.language.nameLocal) == lang }
        }

        // Deduplicate by abbreviation+language — prefer free versions, then first occurrence.
        // This collapses editions like "WEB", "WEB British", "WEB Deuterocanon" into one entry.
        list = list.sorted {
            // Free versions rise to the top so dedup keeps them
            PremiumLimits.freeBibleIds.contains($0.id) && !PremiumLimits.freeBibleIds.contains($1.id)
        }
        var seen = Set<String>()
        list = list.filter { t in
            let key = "\(t.language.id)-\(t.displayAbbreviation)"
            return seen.insert(key).inserted
        }

        // Search filter — diacritic-insensitive so "Espanol" matches "Español", etc.
        guard !searchText.isEmpty else { return list }
        let q = searchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        func normalize(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        return list.filter {
            normalize($0.name).contains(q)
            || normalize($0.abbreviation).contains(q)
            || normalize($0.language.name).contains(q)
            || normalize($0.language.nameLocal).contains(q)
            || normalize($0.nameLocal).contains(q)
        }
    }

    private var availableLanguages: [String] {
        var all = Array(Set(vm.translations.map { langName($0.language.nameLocal) })).sorted()
        // Pin in reverse order so final result is: English, Español, then rest alphabetical
        for pinned in ["Español", "English"] {
            if let idx = all.firstIndex(of: pinned) {
                all.remove(at: idx)
                all.insert(pinned, at: 0)
            }
        }
        return all
    }
}

// MARK: - Translation Row

private struct TranslationRow: View {

    let translation:   BibleTranslation
    let isSelected:    Bool
    var isLocked:      Bool = false
    var isFreeVersion: Bool = false  // true only for free-tier users on a free version

    var body: some View {
        HStack(spacing: 12) {

            // Fixed-width chip — all abbreviations line up regardless of length
            Text(translation.displayAbbreviation)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 56, alignment: .center)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(translation.name)
                    .font(.body)
                    .foregroundStyle(isLocked ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(translation.language.nameLocal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isFreeVersion {
                        Text("Free")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
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
    }
}
