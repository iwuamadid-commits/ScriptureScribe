//
//  CreateAnswerView.swift
//  ScriptureScribe
//
//  Sheet for posting an answer to today's Daily Question.
//  The question is shown at the top (read-only) so the user always sees it while typing.
//

import SwiftUI

struct CreateAnswerView: View {

    let question:    String
    let currentUser: AppUser
    let onPost:      (String) -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var answerText = ""

    private var canPost: Bool {
        !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── Today's question ───────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.bubble.fill")
                                    .foregroundStyle(themeManager.currentTheme.primary)
                                Text("Today's Question")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(themeManager.currentTheme.primary)
                            }
                            Text(question)
                                .font(.subheadline)
                                .foregroundStyle(themeManager.currentTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(themeManager.currentTheme.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 8)

                        // ── Author info ────────────────────────────────
                        HStack(spacing: 10) {
                            UserAvatarView(displayName: currentUser.displayName, photoURL: currentUser.photoURL, size: 34)
                            Text(currentUser.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(themeManager.currentTheme.text)
                        }

                        // ── Text editor ────────────────────────────────
                        ZStack(alignment: .topLeading) {
                            if answerText.isEmpty {
                                Text("Share your answer…")
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $answerText)
                                .frame(minHeight: 140)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                        }
                        .foregroundStyle(themeManager.currentTheme.text)
                        .font(.body)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Share Your Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") {
                        onPost(answerText.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canPost ? themeManager.currentTheme.primary : themeManager.currentTheme.border)
                    .disabled(!canPost)
                }
            }
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
