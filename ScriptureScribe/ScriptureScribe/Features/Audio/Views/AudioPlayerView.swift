//
//  AudioPlayerView.swift
//  ScriptureScribe
//
//  The compact player bar that sits at the bottom of the Reader screen.
//
//  Layout (top to bottom):
//    ▓▓▓▓▓▓░░░░░░░░ ← Slider (scrub bar)
//    0:42              4:31  ← time labels
//    🎤  ⏪  ▶  ⏩  ✕   ← controls row
//

import SwiftUI

struct AudioPlayerView: View {

    @ObservedObject var audioVM: AudioPlayerViewModel
    @EnvironmentObject var themeManager: ThemeManager

    @State private var scrubValue = 0.0
    @State private var showVoices = false

    var body: some View {
        VStack(spacing: 0) {
            scrubBar
            controlsRow
                .padding(.bottom, 6)
        }
        .padding(.top, 8)
        .background(.regularMaterial)
        .sheet(isPresented: $showVoices) {
            VoiceSelectorView(audioVM: audioVM)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Scrub Bar

    private var scrubBar: some View {
        VStack(spacing: 1) {
            Slider(
                value: Binding(
                    get: { audioVM.isSeeking ? scrubValue : audioVM.currentTime },
                    set: { newVal in
                        scrubValue        = newVal
                        audioVM.isSeeking = true
                    }
                ),
                in: 0...max(audioVM.duration, 1)
            ) { editing in
                if !editing {
                    audioVM.isSeeking = false
                    audioVM.seek(to: scrubValue)
                }
            }
            .tint(themeManager.currentTheme.primary)
            .padding(.horizontal, 16)

            HStack {
                Text(audioVM.formatted(audioVM.isSeeking ? scrubValue : audioVM.currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                Spacer()
                Text(audioVM.formatted(audioVM.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack(spacing: 0) {

            // Voice picker
            Button { showVoices = true } label: {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 18))
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .frame(width: 48, height: 44)
            }

            Spacer()

            // −10 s
            Button { audioVM.skip(-10) } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 24))
                    .foregroundStyle(themeManager.currentTheme.text)
                    .frame(width: 48, height: 44)
            }

            // Play / Pause
            Button { audioVM.togglePlayback() } label: {
                Circle()
                    .fill(themeManager.currentTheme.primary)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: audioVM.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: audioVM.isPlaying ? 0 : 2)
                    )
            }
            .padding(.horizontal, 8)

            // +10 s
            Button { audioVM.skip(10) } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 24))
                    .foregroundStyle(themeManager.currentTheme.text)
                    .frame(width: 48, height: 44)
            }

            Spacer()

            // Close
            Button { audioVM.closePlayer() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .frame(width: 48, height: 44)
            }
        }
        .padding(.horizontal, 8)
    }
}
