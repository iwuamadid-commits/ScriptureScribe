//
//  CreatePrayerView.swift
//  ScriptureScribe
//
//  Sheet for posting a prayer request to the community.
//

import SwiftUI

struct CreatePrayerView: View {

    let currentUser: AppUser
    let onPost:      (String) -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var requestText = ""

    private var canPost: Bool {
        !requestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

                        // ── Encouragement note ─────────────────────────
                        HStack(spacing: 8) {
                            Text("🙏")
                            Text("The community will pray for you.")
                                .font(.footnote)
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(themeManager.currentTheme.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // ── Text editor ────────────────────────────────
                        ZStack(alignment: .topLeading) {
                            if requestText.isEmpty {
                                Text("Share your prayer request\u{2026}")
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $requestText)
                                .frame(minHeight: 160)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .onChange(of: requestText) { _, newValue in
                                    if newValue.count > 2000 { requestText = String(newValue.prefix(2000)) }
                                }
                        }
                        .foregroundStyle(themeManager.currentTheme.text)
                        .font(.body)

                        if requestText.count > 1800 {
                            Text("\(requestText.count)/2000")
                                .font(.caption2)
                                .foregroundStyle(requestText.count >= 2000 ? .red : themeManager.currentTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Prayer Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") {
                        onPost(requestText.trimmingCharacters(in: .whitespacesAndNewlines))
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
