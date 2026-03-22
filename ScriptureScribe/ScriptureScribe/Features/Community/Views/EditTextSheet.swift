//
//  EditTextSheet.swift
//  ScriptureScribe
//
//  A reusable sheet for editing the text of a Community post.
//  Used by Reflections, Gratitude, Prayer, and Daily Answer cards.
//

import SwiftUI

struct EditTextSheet: View {

    let title:        String
    let originalText: String
    let onSave:       (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    TextEditor(text: $text)
                        .font(.body)
                        .foregroundStyle(themeManager.currentTheme.text)
                        .scrollContentBackground(.hidden)
                        .padding(16)
                        .onChange(of: text) { _, newValue in
                            if newValue.count > 2000 { text = String(newValue.prefix(2000)) }
                        }

                    if text.count > 1800 {
                        Text("\(text.count)/2000")
                            .font(.caption2)
                            .foregroundStyle(text.count >= 2000 ? .red : themeManager.currentTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 20)
                            .padding(.bottom, 8)
                    }
                }
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
                        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { text = originalText }
    }
}
