//
//  AdminEditPostSheet.swift
//  ScriptureScribe
//
//  Admin-only edit sheet with full control over a post's text,
//  verse reference, verse text, and the author's display name.
//

import SwiftUI

struct AdminEditPostSheet: View {

    let post: Post
    let onSave: (_ text: String, _ verseRef: String, _ verseText: String, _ displayName: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    @State private var text         = ""
    @State private var verseRef     = ""
    @State private var verseText    = ""
    @State private var displayName  = ""

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── Admin badge ──────────────────────────────
                        HStack(spacing: 6) {
                            Image(systemName: "shield.checkered")
                                .foregroundStyle(.orange)
                            Text("Admin Edit")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // ── Display Name ─────────────────────────────
                        fieldSection(label: "Display Name") {
                            TextField("Author name", text: $displayName)
                                .padding(12)
                                .background(themeManager.currentTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(themeManager.currentTheme.border, lineWidth: 1)
                                )
                                .onChange(of: displayName) { _, newValue in
                                    if newValue.count > 50 { displayName = String(newValue.prefix(50)) }
                                }
                        }

                        // ── Verse Reference ──────────────────────────
                        fieldSection(label: "Verse Reference") {
                            TextField("e.g. John 3:16", text: $verseRef)
                                .padding(12)
                                .background(themeManager.currentTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(themeManager.currentTheme.border, lineWidth: 1)
                                )
                        }

                        // ── Verse Text ───────────────────────────────
                        fieldSection(label: "Verse Text") {
                            TextEditor(text: $verseText)
                                .frame(minHeight: 60)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(themeManager.currentTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(themeManager.currentTheme.border, lineWidth: 1)
                                )
                        }

                        // ── Post Text ────────────────────────────────
                        fieldSection(label: "Post Text") {
                            TextEditor(text: $text)
                                .frame(minHeight: 120)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(themeManager.currentTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(themeManager.currentTheme.border, lineWidth: 1)
                                )
                                .onChange(of: text) { _, newValue in
                                    if newValue.count > 2000 { text = String(newValue.prefix(2000)) }
                                }

                            if text.count > 1800 {
                                Text("\(text.count)/2000")
                                    .font(.caption2)
                                    .foregroundStyle(text.count >= 2000 ? .red : themeManager.currentTheme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                    .padding(20)
                }
                .foregroundStyle(themeManager.currentTheme.text)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text, verseRef, verseText, displayName)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canSave ? themeManager.currentTheme.primary : themeManager.currentTheme.border)
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            text        = post.text
            verseRef    = post.verseRef
            verseText   = post.verseText
            displayName = post.displayName
        }
    }

    @ViewBuilder
    private func fieldSection(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(themeManager.currentTheme.textSecondary)
            content()
        }
    }
}
