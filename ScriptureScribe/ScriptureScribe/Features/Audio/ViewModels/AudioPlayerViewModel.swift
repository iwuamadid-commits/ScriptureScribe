//
//  AudioPlayerViewModel.swift
//  ScriptureScribe
//
//  Reads Bible chapters aloud.
//  • First tries API.Bible streaming audio (a real human narrator).
//  • Falls back to iOS text-to-speech if the API has no audio for this translation.
//
//  Progress tracking:
//  • Streaming: AVPlayer's built-in periodic time observer (accurate to the frame).
//  • TTS fallback: a lightweight Timer polling elapsed wall-clock time.
//

import AVFoundation
import Combine
import SwiftUI

@MainActor
final class AudioPlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isVisible    = false
    @Published var isPlaying    = false
    @Published var currentTime  = 0.0   // seconds
    @Published var duration     = 0.0   // seconds
    @Published var isSeeking    = false
    @Published var isBuffering  = false // true while streaming audio loads
    var audioSource = ""   // internal diagnostic only; not displayed

    // MARK: - Preferences

    @AppStorage("preferredVoiceId") var preferredVoiceId: String = ""

    // MARK: - TTS Voice Options (used only when streaming is unavailable)

    struct VoiceOption: Identifiable {
        let id:    String   // AVSpeechSynthesisVoice language code
        let label: String   // display name
    }

    let voiceOptions: [VoiceOption] = [
        VoiceOption(id: "en-US", label: "American English"),
        VoiceOption(id: "en-GB", label: "British English"),
        VoiceOption(id: "en-AU", label: "Australian English"),
        VoiceOption(id: "en-IE", label: "Irish English"),
        VoiceOption(id: "en-IN", label: "Indian English"),
    ]

    var selectedVoice: AVSpeechSynthesisVoice? {
        let lang = preferredVoiceId.isEmpty ? "en-US" : preferredVoiceId
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(lang) }
        return candidates.first(where: { $0.quality == .premium })
            ?? candidates.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: lang)
    }

    // MARK: - Private: Shared

    private var pausedAtTime     = 0.0
    private var currentChapterId = ""
    private var currentBibleId   = ""

    // MARK: - Private: TTS

    private var synthesizer    = AVSpeechSynthesizer()
    private var progressTimer: Timer?
    private var playStartDate: Date?
    private var currentText    = ""
    private let charsPerSecond: Double = 13.0

    // MARK: - Private: Streaming

    private let audioService      = AudioBibleService()
    private var avPlayer:         AVPlayer?
    private var timeObserver:     Any?
    private var playerObserver:   NSObjectProtocol?
    private var isStreamingMode   = false
    private var cachedAudioBibleId: String?   // first audio Bible that returned a valid URL
    private var confirmedNoAudio  = false     // true once we know the API has nothing

    // MARK: - Open / Change Chapter

    func openPlayer(for chapterId: String, text: String, bibleId: String = "") {
        isVisible = true
        guard chapterId != currentChapterId || currentText.isEmpty else { return }

        stopEverything()
        currentChapterId = chapterId
        currentBibleId   = bibleId
        currentText      = cleanText(text)
        duration         = Double(currentText.count) / charsPerSecond   // TTS estimate; updated later if streaming

        // Restore saved position
        let saved = UserDefaults.standard.double(forKey: posKey(chapterId))
        pausedAtTime = min(saved, max(0, duration - 1))
        currentTime  = pausedAtTime

        // Try to get real streaming audio in the background.
        // TTS is ready immediately as a fallback.
        if !bibleId.isEmpty {
            audioSource = "Checking API…"
            Task { await tryStreamingAudio(bibleId: bibleId, chapterId: chapterId) }
        } else {
            audioSource = "Text-to-Speech"
        }
    }

    func updateText(_ text: String, for chapterId: String) {
        guard chapterId == currentChapterId else { return }
        currentText = cleanText(text)
        if !isStreamingMode {
            duration = Double(currentText.count) / charsPerSecond
        }
    }

    func closePlayer() {
        stopEverything()
        isVisible        = false
        confirmedNoAudio = false   // allow a fresh attempt next session
    }

    // MARK: - Playback Controls

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        if isStreamingMode {
            playStreaming()
        } else {
            playTTS()
        }
    }

    func pause() {
        if isStreamingMode {
            avPlayer?.pause()
        } else {
            synthesizer.stopSpeaking(at: .immediate)
            progressTimer?.invalidate()
            progressTimer = nil
        }
        pausedAtTime = currentTime
        isPlaying    = false
        UserDefaults.standard.set(currentTime, forKey: posKey(currentChapterId))
    }

    func skip(_ seconds: Double) {
        seek(to: max(0, min(duration, currentTime + seconds)))
    }

    func seek(to time: Double) {
        pausedAtTime = time
        currentTime  = time
        if isStreamingMode {
            let target = CMTime(seconds: time, preferredTimescale: 600)
            avPlayer?.seek(to: target)
        } else {
            let wasPlaying = isPlaying
            if isPlaying {
                synthesizer.stopSpeaking(at: .immediate)
                progressTimer?.invalidate()
                progressTimer = nil
                isPlaying = false
            }
            if wasPlaying { playTTS() }
        }
    }

    // MARK: - Streaming

    private func tryStreamingAudio(bibleId: String, chapterId: String) async {
        // Skip the whole search if we already know nothing is available.
        guard !confirmedNoAudio else {
            audioSource = "Text-to-Speech"
            return
        }

        do {
            audioSource = "Checking API…"

            // Fast path: we already know which audio Bible works — go straight to the URL.
            if let cachedId = cachedAudioBibleId {
                if let urlString = try? await audioService.fetchChapterURL(
                    audioBibleId: cachedId, chapterId: chapterId),
                   let url = URL(string: urlString) {
                    audioSource = "API Audio"
                    activateStreaming(url: url)
                    return
                }
                // Cached ID stopped working — clear it and fall through to discovery.
                cachedAudioBibleId = nil
            }

            // Discovery pass: build the candidate list.
            // 1. Try the translation-specific match first (most accurate).
            var candidates: [AudioBible] = []
            if !bibleId.isEmpty {
                candidates = (try? await audioService.fetchAudioBibles(bibleId: bibleId)) ?? []
            }
            // 2. If nothing matched, try every English audio Bible the key can access.
            if candidates.isEmpty {
                audioSource = "Searching all English audio…"
                let all = try await audioService.fetchAudioBibles()
                candidates = all.filter { $0.isEnglish }
            }

            guard !candidates.isEmpty else {
                audioSource = "Text-to-Speech"
                confirmedNoAudio = true
                return
            }

            // Try each candidate (up to 8) until one returns a real URL.
            for candidate in candidates.prefix(8) {
                audioSource = "Trying \(candidate.name)…"
                if let urlString = try? await audioService.fetchChapterURL(
                    audioBibleId: candidate.id, chapterId: chapterId),
                   let url = URL(string: urlString) {
                    cachedAudioBibleId = candidate.id   // remember this one for next time
                    audioSource = "API Audio: \(candidate.name)"
                    activateStreaming(url: url)
                    return
                }
            }

            // None of the candidates had a URL — stop trying.
            audioSource = "Text-to-Speech"
            confirmedNoAudio = true

        } catch {
            audioSource = "TTS (\(error.localizedDescription))"
        }
    }

    /// Switches from TTS to AVPlayer streaming, preserving playback position if needed.
    private func activateStreaming(url: URL) {
        let wasPlaying = isPlaying
        let resumeAt   = currentTime

        if wasPlaying && !isStreamingMode {
            synthesizer.stopSpeaking(at: .immediate)
            progressTimer?.invalidate()
            progressTimer = nil
            isPlaying = false
        }

        setupAVPlayer(url: url)

        if wasPlaying {
            pausedAtTime = resumeAt
            playStreaming()
        }
    }

    private func setupAVPlayer(url: URL) {
        cleanupAVPlayer()

        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item   = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        avPlayer       = player
        isStreamingMode = true
        isBuffering    = true

        // Fetch duration from the stream's metadata once it loads.
        Task {
            if let d = try? await item.asset.load(.duration), d.isNumeric {
                duration    = d.seconds
                isBuffering = false
            } else {
                isBuffering = false
            }
        }

        // Track playback time every 0.5 s.
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !self.isSeeking else { return }
                self.currentTime = time.seconds
            }
        }

        // Detect when the chapter finishes playing.
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying    = false
                self.currentTime  = 0
                self.pausedAtTime = 0
                UserDefaults.standard.removeObject(forKey: self.posKey(self.currentChapterId))
            }
        }
    }

    private func playStreaming() {
        guard let player = avPlayer else { return }
        if pausedAtTime > 0 {
            let target = CMTime(seconds: pausedAtTime, preferredTimescale: 600)
            player.seek(to: target) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.avPlayer?.play()
                    self?.isPlaying = true
                }
            }
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func cleanupAVPlayer() {
        if let observer = timeObserver {
            avPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
            playerObserver = nil
        }
        avPlayer?.pause()
        avPlayer        = nil
        isStreamingMode = false
        isBuffering     = false
    }

    // MARK: - TTS

    private func playTTS() {
        guard !currentText.isEmpty else { return }

        let charPos  = max(0, min(Int(pausedAtTime * charsPerSecond), currentText.count - 1))
        let startIdx = currentText.index(currentText.startIndex, offsetBy: charPos)
        let slice    = String(currentText[startIdx...])
        guard !slice.isEmpty else { return }

        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        synthesizer.stopSpeaking(at: .immediate)

        let utterance   = AVSpeechUtterance(string: slice)
        utterance.voice = selectedVoice
        utterance.rate  = AVSpeechUtteranceDefaultSpeechRate

        synthesizer.speak(utterance)
        isPlaying     = true
        playStartDate = Date()
        startProgressTimer(from: pausedAtTime)
    }

    // MARK: - TTS Timer

    private func startProgressTimer(from startTime: Double) {
        progressTimer?.invalidate()
        let capturedDate = playStartDate ?? Date()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isPlaying, !self.isStreamingMode else { return }
                let elapsed = Date().timeIntervalSince(capturedDate)
                let newTime = startTime + elapsed
                if !self.isSeeking { self.currentTime = min(newTime, self.duration) }

                if !self.synthesizer.isSpeaking && !self.synthesizer.isPaused {
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                    self.isPlaying    = false
                    self.currentTime  = 0
                    self.pausedAtTime = 0
                    UserDefaults.standard.removeObject(
                        forKey: self.posKey(self.currentChapterId))
                }
            }
        }
    }

    // MARK: - Stop Everything

    private func stopEverything() {
        synthesizer.stopSpeaking(at: .immediate)
        progressTimer?.invalidate()
        progressTimer = nil
        cleanupAVPlayer()
        isPlaying    = false
        currentTime  = 0
        pausedAtTime = 0
    }

    // MARK: - Helpers

    private func cleanText(_ raw: String) -> String {
        var text = raw
        if let regex = try? NSRegularExpression(pattern: "\\[\\d+\\]\\s*") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func posKey(_ chapterId: String) -> String { "ttsPos_\(chapterId)" }

    func formatted(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let t = Int(seconds)
        return "\(t / 60):\(String(format: "%02d", t % 60))"
    }
}
