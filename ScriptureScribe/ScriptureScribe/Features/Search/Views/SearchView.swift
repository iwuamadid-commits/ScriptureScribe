//
//  SearchView.swift
//  ScriptureScribe
//
//  Three-mode Bible search screen:
//    • Text        — type a word or phrase, get matching verses from API.Bible
//    • Topics      — tap a preset topic (Faith, Hope, Love…) to see related verses
//    • Handwriting — draw a word with Apple Pencil, OCR reads it, then searches
//
//  The search always runs against the same translation the user was reading
//  in the Reader tab (shared via @AppStorage("lastBibleId")).
//

import SwiftUI
import PencilKit
import Vision

// MARK: - SearchView

struct SearchView: View {

    @StateObject private var vm = SearchViewModel()
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var appNav:       AppNavigation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Mode picker ──────────────────────────────────────────────
                Picker("Search mode", selection: $vm.searchMode) {
                    ForEach(SearchViewModel.SearchMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // ── Mode content ─────────────────────────────────────────────
                switch vm.searchMode {
                case .text:        textSearchTab
                case .topics:      topicsTab
                case .handwriting: handwritingTab
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: vm.searchMode) { _, _ in
                vm.clearResults()
            }
        }
    }

    // MARK: - Text Search Tab

    @ViewBuilder
    private var textSearchTab: some View {
        VStack(spacing: 0) {
            searchBar
            // "Go to" book/chapter suggestions above results
            if !vm.goToSuggestions.isEmpty {
                goToSuggestionsSection
            }
            // Show recent searches when idle; results otherwise
            if vm.query.isEmpty && vm.results.isEmpty && !vm.isLoading && !vm.recentSearches.isEmpty {
                recentSearchesSection
            } else {
                resultsContent
            }
        }
    }

    // MARK: - Recent Searches

    private var recentSearchesSection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                    Spacer()
                    Button("Clear") { vm.clearAllRecentSearches() }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

                ForEach(vm.recentSearches, id: \.self) { term in
                    HStack(spacing: 0) {
                        Button {
                            vm.query = term
                            vm.updateGoToSuggestions()
                            // If the term is a book/reference, just show "Go to" suggestions
                            // instead of hitting the API (which would error on book names).
                            if vm.goToSuggestions.isEmpty {
                                Task { await vm.search() }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .font(.subheadline)
                                Text(term)
                                    .foregroundStyle(themeManager.currentTheme.text)
                                    .font(.body)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            vm.removeRecentSearch(term)
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                                .font(.caption2)
                                .padding(.trailing, 16)
                                .padding(.vertical, 13)
                        }
                        .accessibilityLabel("Remove search")
                    }
                    Divider().padding(.leading, 48)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var hwRecentSearchesSection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                    Spacer()
                    Button("Clear") { vm.clearAllHwRecentSearches() }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

                ForEach(vm.hwRecentSearches, id: \.self) { term in
                    HStack(spacing: 0) {
                        Button {
                            vm.hwQuery = term
                            vm.searchHandwriting()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .font(.subheadline)
                                Text(term)
                                    .foregroundStyle(themeManager.currentTheme.text)
                                    .font(.body)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            vm.removeHwRecentSearch(term)
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                                .font(.caption2)
                                .padding(.trailing, 16)
                                .padding(.vertical, 13)
                        }
                        .accessibilityLabel("Remove search")
                    }
                    Divider().padding(.leading, 48)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Go-To Suggestions

    private var goToSuggestionsSection: some View {
        VStack(spacing: 0) {
            ForEach(vm.goToSuggestions) { suggestion in
                Button {
                    if let chapId = suggestion.chapterId {
                        if let verse = suggestion.verseNum {
                            appNav.pendingVerseNumber = verse
                        }
                        appNav.pendingChapterId = chapId
                        appNav.selectedTab = 0
                        vm.addRecentSearch(suggestion.label)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.fill")
                            .foregroundStyle(themeManager.currentTheme.primary)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Go to \(suggestion.label)")
                                .font(.body.weight(.medium))
                                .foregroundStyle(themeManager.currentTheme.text)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 48)
            }
        }
        .background(themeManager.currentTheme.surface.opacity(0.5))
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(themeManager.currentTheme.textSecondary)
            TextField("Search the Bible…", text: $vm.query)
                .submitLabel(.search)
                .onSubmit { Task { await vm.search() } }
                .onChange(of: vm.query) { _, _ in vm.liveSearch() }
            if !vm.query.isEmpty {
                Button {
                    vm.query           = ""
                    vm.results         = []
                    vm.errorMessage    = nil
                    vm.goToSuggestions = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .foregroundStyle(themeManager.currentTheme.text)   // TextField inherits from HStack
        .padding(12)
        .background(themeManager.currentTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.currentTheme.border.opacity(0.6), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Topics Tab

    @ViewBuilder
    private var topicsTab: some View {
        if vm.selectedTopic != nil || !vm.results.isEmpty || vm.isLoading || vm.errorMessage != nil {
            // Showing results for the selected topic
            VStack(spacing: 0) {
                topicResultsHeader
                resultsContent
            }
        } else {
            // Topic grid
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(vm.topics) { topic in
                        TopicCard(topic: topic, theme: themeManager.currentTheme) {
                            Task { await vm.searchTopic(topic) }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var topicResultsHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    vm.clearResults()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.callout.weight(.semibold))
                        Text("All Topics")
                            .font(.callout.weight(.medium))
                    }
                    .foregroundStyle(themeManager.currentTheme.primary)
                }

                Spacer()

                if let topic = vm.selectedTopic {
                    Text(topic.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.text)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()
        }
    }

    // MARK: - Handwriting Tab (GoodNotes-style index search)

    @ViewBuilder
    private var handwritingTab: some View {
        VStack(spacing: 0) {
            // ── Search bar ───────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "hand.writing")
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                TextField("Search your handwritten notes…", text: $vm.hwQuery)
                    .submitLabel(.search)
                    .onSubmit { vm.searchHandwriting(saveToRecents: true) }
                    .onChange(of: vm.hwQuery) { _, _ in vm.searchHandwriting() }
                if !vm.hwQuery.isEmpty {
                    Button {
                        vm.hwQuery   = ""
                        vm.hwResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .foregroundStyle(themeManager.currentTheme.text)   // TextField inherits from HStack
            .padding(12)
            .background(themeManager.currentTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeManager.currentTheme.border.opacity(0.6), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // ── Results / empty states ───────────────────────────────────────
            if vm.hwQuery.isEmpty {
                if !vm.hwRecentSearches.isEmpty {
                    // Show recent handwriting searches
                    hwRecentSearchesSection
                } else {
                    Spacer()
                    if HandwritingIndexService.shared.hasAnyIndex {
                        emptyState(
                            icon: "text.magnifyingglass",
                            message: "Type a word above to search everything you've written in the margins."
                        )
                    } else {
                        emptyState(
                            icon: "pencil.and.scribble",
                            message: "Your handwritten margin notes will appear here once you've written in the Bible + Notebook view.\n\nSwitch to Reader, choose \"Bible + Notebook\" layout, and start writing!"
                        )
                    }
                    Spacer()
                }
            } else if vm.hwResults.isEmpty {
                Spacer()
                emptyState(
                    icon: "doc.text.magnifyingglass",
                    message: "No handwritten notes found for \"\(vm.hwQuery)\""
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.hwResults) { match in
                            HandwritingMatchRow(
                                match:  match,
                                theme:  themeManager.currentTheme,
                                onOpen: {
                                    appNav.pendingChapterId = match.chapterId
                                    dismiss()
                                }
                            )
                            .padding(.horizontal, 16)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.currentTheme.background)
    }

    // MARK: - Shared Results List (Text + Topics)

    @ViewBuilder
    private var resultsContent: some View {
        if vm.isLoading {
            Spacer()
            ProgressView()
            Spacer()
        } else if let error = vm.errorMessage {
            Spacer()
            emptyState(icon: "exclamationmark.triangle", message: error)
            Spacer()
        } else if vm.results.isEmpty && !vm.query.isEmpty && vm.goToSuggestions.isEmpty {
            Spacer()
            emptyState(
                icon: "doc.text.magnifyingglass",
                message: "No results found for \"\(vm.query)\""
            )
            Spacer()
        } else if !vm.results.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.results) { result in
                        Button {
                            // Verse ID "GEN.1.16" → chapter "GEN.1", verse "16"
                            let parts = result.id.components(separatedBy: ".")
                            if parts.count >= 2 {
                                if parts.count >= 3 {
                                    appNav.pendingVerseNumber = parts[2]
                                }
                                appNav.pendingChapterId = "\(parts[0]).\(parts[1])"
                                vm.addRecentSearch(vm.query)
                                dismiss()
                            }
                        } label: {
                            SearchResultRow(result: result, theme: themeManager.currentTheme, query: vm.query)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.horizontal, 16)
                    }
                }
                .background(themeManager.currentTheme.background)
            }
            .scrollDismissesKeyboard(.immediately)
        } else {
            Spacer()
        }
    }

    // MARK: - Empty State Helper

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .padding(.top, 40)
    }
}

// MARK: - Topic Card

private struct TopicCard: View {

    let topic:  BibleTopic
    let theme:  any AppTheme
    let onTap:  () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Image(systemName: topic.icon)
                    .font(.title)
                    .foregroundStyle(theme.primary)
                Text(topic.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(theme.border.opacity(0.4), lineWidth: 1)
            )
        }
    }
}

// MARK: - Search Highlighting Helper

/// Builds a SwiftUI Text where every occurrence of `query` is bold and coloured.
/// Uses AttributedString (iOS 15+) to avoid the deprecated Text + Text operator.
private func highlighted(
    _ text:          String,
    query:           String,
    baseColor:       Color,
    highlightColor:  Color,
    font:            Font = .body
) -> Text {
    let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else {
        return Text(text).font(font).foregroundStyle(baseColor)
    }

    // Start with the full string styled in the base colour and font.
    var attributed = AttributedString(text)
    attributed.swiftUI.font            = font
    attributed.swiftUI.foregroundColor = baseColor

    // Walk through every case-insensitive match and apply bold + highlight colour.
    let lower = text.lowercased()
    var searchStart = lower.startIndex

    while let range = lower.range(of: q, range: searchStart..<lower.endIndex) {
        // Translate String.Index offsets to AttributedString.Index.
        let lowerOff = lower.distance(from: lower.startIndex, to: range.lowerBound)
        let upperOff = lower.distance(from: lower.startIndex, to: range.upperBound)
        let attrLow  = attributed.index(attributed.startIndex, offsetByCharacters: lowerOff)
        let attrHigh = attributed.index(attributed.startIndex, offsetByCharacters: upperOff)

        attributed[attrLow..<attrHigh].swiftUI.font            = font.bold()
        attributed[attrLow..<attrHigh].swiftUI.foregroundColor = highlightColor

        searchStart = range.upperBound
    }

    return Text(attributed)
}

// MARK: - Search Result Row

private struct SearchResultRow: View {

    let result: SearchResult
    let theme:  any AppTheme
    let query:  String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.reference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primary)
            highlighted(result.text,
                        query:          query,
                        baseColor:      theme.text,
                        highlightColor: theme.searchHighlight)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }
}

// MARK: - Handwriting Match Row

private struct HandwritingMatchRow: View {

    let match:  HandwritingMatch
    let theme:  any AppTheme
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(match.reference)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primary)
                    highlighted(match.snippet,
                                query:          match.query,
                                baseColor:      theme.text.opacity(0.75),
                                highlightColor: theme.searchHighlight,
                                font:           .footnote)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 2)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Handwriting Canvas

/// A transparent PKCanvasView wrapper controlled via SwiftUI bindings.
/// Set `shouldClear = true` to wipe the canvas.
/// Set `shouldRecognize = true` to trigger Vision OCR — result arrives via `onRecognized`.
private struct HandwritingCanvasView: UIViewRepresentable {

    @Binding var shouldClear:     Bool
    @Binding var shouldRecognize: Bool
    let onRecognized:             (String) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas             = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque        = false
        canvas.drawingPolicy   = .anyInput   // finger or Apple Pencil
        canvas.tool            = PKInkingTool(.pen, color: UIColor.label, width: 4)
        context.coordinator.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if shouldClear {
            canvas.drawing = PKDrawing()
            DispatchQueue.main.async { shouldClear = false }
        }
        if shouldRecognize {
            context.coordinator.recognize(from: canvas)
            DispatchQueue.main.async { shouldRecognize = false }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onRecognized: onRecognized) }

    final class Coordinator: NSObject {
        weak var canvas: PKCanvasView?
        let onRecognized: (String) -> Void

        init(onRecognized: @escaping (String) -> Void) {
            self.onRecognized = onRecognized
        }

        func recognize(from canvas: PKCanvasView) {
            guard !canvas.drawing.strokes.isEmpty else {
                DispatchQueue.main.async { self.onRecognized("") }
                return
            }

            // Render the drawing to an image, padded slightly for better OCR accuracy
            let raw    = canvas.drawing.bounds
            let bounds = raw.isEmpty
                ? canvas.bounds
                : raw.insetBy(dx: -24, dy: -24)
            let scale  = canvas.traitCollection.displayScale
            let image  = canvas.drawing.image(from: bounds, scale: scale)

            guard let cgImage = image.cgImage else {
                DispatchQueue.main.async { self.onRecognized("") }
                return
            }

            // Run Vision text recognition on a background thread
            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async { self.onRecognized(text) }
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = false   // preserve the literal word written

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
            }
        }
    }
}
