//
//  AdminEditTextSheet.swift
//  ScriptureScribe
//
//  Admin-only edit sheet for posts without verse fields (Gratitude, Prayer, Daily).
//  Allows editing both the post text and the author's display name.
//

import SwiftUI

struct AdminEditTextSheet: View {

    let title: String
    let originalText: String
    let originalDisplayName: String
    let onSave: (_ text: String, _ displayName: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    @State private var text        = ""
    @State private var displayName = ""

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

                        // ── Admin badge ─────────────────────────────
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Display Name")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
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

                        // ── Post Text ────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Post Text")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                            TextEditor(text: $text)
                                .frame(minHeight: 160)
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
            .navigationTitle(title)
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
                        onSave(text, displayName)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canSave ? themeManager.currentTheme.primary : themeManager.currentTheme.border)
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            text        = originalText
            displayName = originalDisplayName
        }
    }
}
