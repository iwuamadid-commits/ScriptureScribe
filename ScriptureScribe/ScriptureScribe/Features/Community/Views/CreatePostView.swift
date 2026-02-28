//
//  CreatePostView.swift
//  ScriptureScribe
//
//  Sheet for writing and posting a reflection to the community feed.
//  Optionally, the user can attach a Bible verse to their post.
//
//  Verse picker flow (when the user taps "Add Verse"):
//    1. A verse picker sheet opens showing a text field to type a reference
//       (e.g. "John 3:16") — stored as a plain string.
//    2. No complex book/chapter/verse tree is needed for the MVP.
//

import SwiftUI

struct CreatePostView: View {

    let currentUser:  AppUser
    let onPost:       (String, String, String) -> Void   // (text, verseRef, verseText)

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var postText      = ""
    @State private var verseRef      = ""   // e.g. "John 3:16"
    @State private var verseText     = ""   // the actual verse text
    @State private var showVersePicker = false

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

                        // ── Verse attachment (optional) ────────────────
                        if !verseRef.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "book.closed.fill")
                                            .font(.caption)
                                            .foregroundStyle(themeManager.currentTheme.primary)
                                        Text(verseRef)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(themeManager.currentTheme.primary)
                                        Spacer()
                                        Button {
                                            verseRef = ""
                                            verseText = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                                        }
                                    }
                                    if !verseText.isEmpty {
                                        Text(verseText)
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
                                Text("Share a reflection, prayer, or thought…")
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $postText)
                                .frame(minHeight: 160)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                        }
                        .foregroundStyle(themeManager.currentTheme.text)
                        .font(.body)

                        // ── Add verse button ───────────────────────────
                        if verseRef.isEmpty {
                            Button {
                                showVersePicker = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "book.closed")
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                    Text("Add a verse")
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(themeManager.currentTheme.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
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
                        onPost(
                            postText.trimmingCharacters(in: .whitespacesAndNewlines),
                            verseRef,
                            verseText
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
            .sheet(isPresented: $showVersePicker) {
                VerseReferencePickerView(verseRef: $verseRef, verseText: $verseText)
            }
        }
    }
}

// MARK: - Verse Reference Picker

/// Sheet where the user types a reference like "John 3:16".
/// • While typing the book name, matching book names appear as suggestions.
/// • Once a full chapter:verse reference is recognized, the verse text is
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
                            Text("Looking up verse…")
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
                    Button("Cancel") { dismiss() }
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
        guard !trimmed.isEmpty else { isFetching = false; return }

        let hasDigit = trimmed.contains(where: { $0.isNumber })

        // No digits yet → show matching book names
        if !hasDigit {
            bookMatches = BibleReferenceParser.bookSuggestions(for: trimmed)
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
