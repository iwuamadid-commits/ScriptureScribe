//
//  VoiceSelectorView.swift
//  ScriptureScribe
//
//  Lets the user pick from 5 built-in English narrator accents.
//

import SwiftUI

struct VoiceSelectorView: View {

    @ObservedObject var audioVM: AudioPlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        NavigationStack {
            List(audioVM.voiceOptions) { option in
                Button {
                    audioVM.preferredVoiceId = option.id
                    dismiss()
                } label: {
                    HStack {
                        Text(option.label)
                            .font(.body)
                            .foregroundStyle(themeManager.currentTheme.text)
                        Spacer()
                        if audioVM.preferredVoiceId == option.id ||
                           (audioVM.preferredVoiceId.isEmpty && option.id == "en-US") {
                            Image(systemName: "checkmark")
                                .foregroundStyle(themeManager.currentTheme.primary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Choose a Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
