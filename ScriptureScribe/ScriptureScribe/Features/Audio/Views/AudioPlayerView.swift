//
//  AudioPlayerView.swift
//  ScriptureScribe
//
//  The compact player bar that sits at the bottom of the Reader screen.
//
//  Layout (top to bottom):
//    John 3  •  NIV                          ✕   ← header (chapter + close)
//    ▓▓▓▓▓▓░░░░░░░░                              ← Slider (scrub bar)
//    0:42                            4:31         ← time labels
//    🎤  ⏪10  ⏮  ▶  ⏭  ⏩10  [1x]              ← controls row
//

import SwiftUI

struct AudioPlayerView: View {

    @ObservedObject var audioVM: AudioPlayerViewModel
    @EnvironmentObject var themeManager: ThemeManager

    @State private var scrubValue = 0.0
    @State private var showVoices = false

    private let speedSteps: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            scrubBar
            controlsRow
                .padding(.bottom, 6)
        }
        .padding(.top, 4)
        .background(.regularMaterial)
        .sheet(isPresented: $showVoices) {
            VoiceSelectorView(audioVM: audioVM)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack {
            Text(audioVM.currentReference.isEmpty ? "Now Playing" : audioVM.currentReference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.currentTheme.text)
                .lineLimit(1)
            Spacer()
            Button { audioVM.closePlayer() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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
                    .font(.system(size: 22))
                    .foregroundStyle(themeManager.currentTheme.text)
                    .frame(width: 44, height: 44)
            }

            // Previous verse
            Button { audioVM.skipToPreviousVerse() } label: {
                Image(systemName: "backward.end.alt.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(themeManager.currentTheme.text)
                    .frame(width: 40, height: 44)
            }

            // Play / Pause
            Button { audioVM.togglePlayback() } label: {
                Circle()
                    .fill(themeManager.currentTheme.primary)
                    .frame(width: 52, height: 52)
                    .overlay {
                        if audioVM.isPreparingTTS {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: audioVM.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: audioVM.isPlaying ? 0 : 2)
                        }
                    }
            }
            .disabled(audioVM.isPreparingTTS)
            .padding(.horizontal, 6)

            // Next verse
            Button { audioVM.skipToNextVerse() } label: {
                Image(systemName: "forward.end.alt.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(themeManager.currentTheme.text)
                    .frame(width: 40, height: 44)
            }

            // +10 s
            Button { audioVM.skip(10) } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 22))
                    .foregroundStyle(themeManager.currentTheme.text)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // Speed — tap to cycle through preset rates
            speedButton
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Speed Button

    private var speedButton: some View {
        Button {
            let i = speedSteps.firstIndex(of: audioVM.playbackRate) ?? 2
            audioVM.playbackRate = speedSteps[(i + 1) % speedSteps.count]
        } label: {
            Text(speedLabel(audioVM.playbackRate))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(themeManager.currentTheme.primary)
                .frame(width: 48, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(themeManager.currentTheme.primary.opacity(
                            audioVM.playbackRate == 1.0 ? 0.0 : 0.12
                        ))
                )
        }
    }

    private func speedLabel(_ rate: Float) -> String {
        if rate == Float(Int(rate)) { return "\(Int(rate))x" }
        return "\(String(format: "%g", rate))x"
    }
}
