//
//  CreatePostView.swift
//  ScriptureScribe
//
//  Sheet for writing and posting a reflection to the community feed.
//  Users can attach one or more Bible verses — consecutive, non-consecutive, or individual.
//
//  Verse picker flow (when the user taps "Add Verse"):
//    1. A verse picker sheet opens showing a text field to type a reference
//       (e.g. "John 3:16") — stored as a plain string.
//    2. Tapping the fetched verse attaches it. User can add more verses.
//

import SwiftUI

struct CreatePostView: View {

    let currentUser:  AppUser
    let onPost:       (String, String, String) -> Void   // (text, verseRef, verseText)

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var postText      = ""
    /// Each attached verse stored as (reference, text).
    @State private var verses: [(ref: String, text: String)] = []
    @State private var showVersePicker = false
    /// Temporary bindings used by the verse picker sheet.
    @State private var pickerRef  = ""
    @State private var pickerText = ""

    private var canPost: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── Author info ────────────────────────────────
                        HStack(spacing: 10) {
                            UserAvatarView(displayName: currentUser.displayName, photoURL: currentUser.photoURL, size: 38)
                            Text(currentUser.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(themeManager.currentTheme.text)
                        }
                        .padding(.top, 8)

                        // ── Attached verses ──────────────────────────────
                        ForEach(Array(verses.enumerated()), id: \.offset) { index, verse in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "book.closed.fill")
                                            .font(.caption)
                                            .foregroundStyle(themeManager.currentTheme.primary)
                                        Text(verse.ref)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(themeManager.currentTheme.primary)
                                        Spacer()
                                        Button {
                                            verses.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                                        }
                                    }
                                    if !verse.text.isEmpty {
                                        Text(verse.text)
                                            .font(.footnote.italic())
                                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    }
                                }
                            }
                            .padding(12)
                            .background(themeManager.currentTheme.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // ── Main text editor ───────────────────────────
                        ZStack(alignment: .topLeading) {
                            if postText.isEmpty {
                                Text("Share a reflection, prayer, or thought\u{2026}")
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $postText)
                                .frame(minHeight: 160)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .onChange(of: postText) { _, newValue in
                                    if newValue.count > 2000 { postText = String(newValue.prefix(2000)) }
                                }
                        }
                        .foregroundStyle(themeManager.currentTheme.text)
                        .font(.body)

                        if postText.count > 1800 {
                            Text("\(postText.count)/2000")
                                .font(.caption2)
                                .foregroundStyle(postText.count >= 2000 ? .red : themeManager.currentTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        // ── Add verse button (always visible) ────────
                        Button {
                            pickerRef  = ""
                            pickerText = ""
                            showVersePicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "book.closed")
                                    .foregroundStyle(themeManager.currentTheme.primary)
                                Text(verses.isEmpty ? "Add a verse" : "Add another verse")
                                    .foregroundStyle(themeManager.currentTheme.primary)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(themeManager.currentTheme.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("New Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") {
                        // Combine all verse refs and texts with separators
                        let combinedRef  = verses.map(\.ref).joined(separator: "; ")
                        let combinedText = verses.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
                        onPost(
                            postText.trimmingCharacters(in: .whitespacesAndNewlines),
                            combinedRef,
                            combinedText
                        )
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canPost ? themeManager.currentTheme.primary : themeManager.currentTheme.border)
                    .disabled(!canPost)
                }
            }
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showVersePicker, onDismiss: {
                // When the picker closes, add the verse if a ref was set
                let ref = pickerRef.trimmingCharacters(in: .whitespaces)
                if !ref.isEmpty {
                    verses.append((ref: ref, text: pickerText))
                }
            }) {
                VerseReferencePickerView(verseRef: $pickerRef, verseText: $pickerText)
            }
        }
    }
}

// MARK: - Verse Reference Picker

/// Sheet where the user types a reference like "John 3:16".
/// - While typing the book name, matching book names appear as suggestions.
/// - Once a full chapter:verse reference is recognized, the verse text is
///   auto-fetched from API.Bible and shown as a one-tap "Attach" card.
private struct VerseReferencePickerView: View {

    @Binding var verseRef:  String
    @Binding var verseText: String

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    // Read the same key that ReaderViewModel stores so we use the user's current translation.
    @AppStorage("lastBibleId") private var storedBibleId: String = ""

    @State private var draftRef       = ""
    @State private var bookMatches:   [(name: String, apiId: String)] = []
    @State private var fetchedVerse:  DailyVerse? = nil
    @State private var isFetching     = false
    @State private var fetchTask:     Task<Void, Never>? = nil
    @State private var selectedBookName: String? = nil

    private let api = BibleAPIService()

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {

                    // ── Reference field ────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type a verse reference")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                        TextField("e.g. John 3:16", text: $draftRef)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(themeManager.currentTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeManager.currentTheme.border, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // ── Book name suggestions ──────────────────────────
                    if !bookMatches.isEmpty {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(bookMatches, id: \.apiId) { match in
                                    Button {
                                        // Fill in the book name and leave a trailing space
                                        // so the user can immediately type the chapter number.
                                        selectedBookName = match.name
                                        draftRef = match.name + " "
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "book.closed")
                                                .font(.subheadline)
                                                .foregroundStyle(themeManager.currentTheme.primary)
                                            Text(match.name)
                                                .font(.body)
                                                .foregroundStyle(themeManager.currentTheme.text)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(themeManager.currentTheme.border)
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 13)
                                    }
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                        .padding(.top, 8)

                    // ── Fetched verse card ─────────────────────────────
                    } else if let verse = fetchedVerse {
                        Button {
                            verseRef  = verse.reference
                            verseText = verse.text
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                    Text(verse.reference)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                    Spacer()
                                    Text("Tap to attach")
                                        .font(.caption)
                                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                                }
                                Text(verse.text)
                                    .font(.footnote)
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(14)
                            .background(themeManager.currentTheme.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeManager.currentTheme.primary.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // ── Loading indicator ──────────────────────────────
                    } else if isFetching {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Looking up verse\u{2026}")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    // ── Hint after book selected ─────────────────────
                    } else if selectedBookName != nil && !draftRef.trimmingCharacters(in: .whitespaces).isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(themeManager.currentTheme.primary)
                            Text("Type chapter:verse (e.g. 3:16)")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Add Verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        // Clear so onDismiss doesn't add a verse
                        verseRef  = ""
                        verseText = ""
                        dismiss()
                    }
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        let ref = draftRef.trimmingCharacters(in: .whitespaces)
                        if let v = fetchedVerse {
                            verseRef  = v.reference
                            verseText = v.text
                        } else {
                            verseRef  = ref
                            verseText = ""
                        }
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        draftRef.trimmingCharacters(in: .whitespaces).isEmpty
                            ? themeManager.currentTheme.border
                            : themeManager.currentTheme.primary
                    )
                    .disabled(draftRef.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { draftRef = verseRef }
        .onChange(of: draftRef) { _, newValue in handleInput(newValue) }
    }

    // MARK: - Input Handling

    private func handleInput(_ text: String) {
        fetchTask?.cancel()
        fetchTask    = nil
        bookMatches  = []
        fetchedVerse = nil

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { isFetching = false; selectedBookName = nil; return }

        // If user edits back to change the book, clear the selection
        if let selected = selectedBookName,
           !trimmed.lowercased().hasPrefix(selected.lowercased()) {
            selectedBookName = nil
        }

        let hasDigit = trimmed.contains(where: { $0.isNumber })

        // No digits yet → show matching book names (but not if a book is already selected)
        if !hasDigit {
            if selectedBookName == nil {
                let matches = BibleReferenceParser.bookSuggestions(for: trimmed)
                // If the typed text exactly matches a single book, auto-select it
                if matches.count == 1, matches[0].name.lowercased() == trimmed.lowercased() {
                    selectedBookName = matches[0].name
                } else {
                    bookMatches = matches
                }
            }
            return
        }

        // Has a colon → looks like a full "Book Chapter:Verse" reference; try to fetch
        guard trimmed.contains(":"),
              let verseId = BibleReferenceParser.verseId(from: trimmed),
              !storedBibleId.isEmpty            // only fetch if user has opened the Reader
        else { return }

        isFetching = true
        fetchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)   // 0.5s debounce
                let verse = try await api.fetchVerse(bibleId: storedBibleId, verseId: verseId)
                await MainActor.run {
                    isFetching   = false
                    fetchedVerse = verse
                }
            } catch {
                await MainActor.run { isFetching = false }
            }
        }
    }
}
