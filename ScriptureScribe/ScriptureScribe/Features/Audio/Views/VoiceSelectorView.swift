//
//  VoiceSelectorView.swift
//  ScriptureScribe
//
//  Shows all English voices installed on the device, grouped by quality tier.
//  The user picks one; the selection is stored by voice identifier.
//

import AVFoundation
import SwiftUI

struct VoiceSelectorView: View {

    @ObservedObject var audioVM: AudioPlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    // Group voices by quality tier
    private var premiumVoices:  [AudioPlayerViewModel.VoiceOption] { audioVM.availableVoices.filter { $0.quality == .premium } }
    private var enhancedVoices: [AudioPlayerViewModel.VoiceOption] { audioVM.availableVoices.filter { $0.quality == .enhanced } }
    private var standardVoices: [AudioPlayerViewModel.VoiceOption] { audioVM.availableVoices.filter { $0.quality == .default } }

    var body: some View {
        NavigationStack {
            List {
                if !premiumVoices.isEmpty {
                    Section("Premium") {
                        ForEach(premiumVoices) { voice in
                            voiceRow(voice)
                        }
                    }
                }

                if !enhancedVoices.isEmpty {
                    Section("Enhanced") {
                        ForEach(enhancedVoices) { voice in
                            voiceRow(voice)
                        }
                    }
                }

                if !standardVoices.isEmpty {
                    Section("Standard") {
                        ForEach(standardVoices) { voice in
                            voiceRow(voice)
                        }
                    }
                }

                Section {
                    // Footer tip
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Want more voices?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(themeManager.currentTheme.text)
                        Text("Go to **Settings → Accessibility → Read & Speak → Voices → English** to download free premium voices.")
                            .font(.footnote)
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(themeManager.currentTheme.background)
            .navigationTitle("Choose a Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
        }
    }

    @ViewBuilder
    private func voiceRow(_ voice: AudioPlayerViewModel.VoiceOption) -> some View {
        let isSelected = audioVM.preferredVoiceIdentifier == voice.id

        Button {
            audioVM.preferredVoiceIdentifier = voice.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name)
                        .font(.body)
                        .foregroundStyle(themeManager.currentTheme.text)
                    Text(voice.language)
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }

                Spacer()

                qualityBadge(voice.quality)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(themeManager.currentTheme.surface)
    }

    @ViewBuilder
    private func qualityBadge(_ quality: AVSpeechSynthesisVoiceQuality) -> some View {
        switch quality {
        case .premium:
            Text("Premium")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(themeManager.currentTheme.primary))
        case .enhanced:
            Text("Enhanced")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().stroke(themeManager.currentTheme.primary, lineWidth: 1))
        default:
            EmptyView()
        }
    }
}
