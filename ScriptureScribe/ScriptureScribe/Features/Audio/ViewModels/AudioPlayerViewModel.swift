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
//  Auto-scroll:
//  • currentVerseNumber is published whenever the active verse changes.
//  • ReaderView observes it and calls verseScrollOffset to follow the audio.
//

import AVFoundation
import Combine
import SwiftUI

@MainActor
final class AudioPlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isVisible      = false
    @Published var isPlaying      = false
    @Published var currentTime    = 0.0   // seconds (wall-clock)
    @Published var duration       = 0.0   // seconds (at current playback speed)
    @Published var isSeeking      = false
    @Published var isBuffering    = false // true while streaming audio loads
    @Published var isPreparingTTS = false // true while Claude reformats text

    /// Displayed in the player header (e.g. "John 3")
    @Published var currentReference   = ""

    /// Current verse being spoken ("1", "2", …; "" = none). Drives reader auto-scroll.
    @Published var currentVerseNumber = ""

    /// Pulses true then immediately back to false when a chapter finishes playing naturally.
    /// ReaderView observes this to auto-advance to the next chapter like an audiobook.
    @Published var chapterDidFinish = false

    /// User-selected playback speed. Applies immediately to AVPlayer; restarts TTS.
    @Published var playbackRate: Float = 1.0 {
        didSet {
            guard oldValue != playbackRate else { return }
            if isStreamingMode {
                avPlayer?.rate = isPlaying ? playbackRate : 0
            } else if isPlaying {
                let savedTime = currentTime
                synthesizer.stopSpeaking(at: .immediate)
                progressTimer?.invalidate()
                progressTimer = nil
                isPlaying    = false
                pausedAtTime = savedTime
                // playTTS() will set duration from the reformatted text length — don't override below.
                playTTS()
                return
            }
            // Paused: estimate duration from cleanText length (playTTS will correct it when played).
            if !isStreamingMode, !currentText.isEmpty {
                duration = Double(currentText.count) / (charsPerSecond * Double(playbackRate))
            }
        }
    }

    var audioSource = ""   // internal diagnostic only; not displayed

    // MARK: - Preferences

    @AppStorage("preferredVoiceIdentifier") var preferredVoiceIdentifier: String = ""

    // MARK: - TTS Voice Options (dynamically built from installed system voices)

    struct VoiceOption: Identifiable {
        let id:      String                        // AVSpeechSynthesisVoice.identifier
        let name:    String                        // display name, e.g. "Samantha"
        let quality: AVSpeechSynthesisVoiceQuality
        let language: String                       // e.g. "en-US"
    }

    /// All English voices installed on this device, sorted: Premium → Enhanced → Default.
    var availableVoices: [VoiceOption] {
        let order: [AVSpeechSynthesisVoiceQuality] = [.premium, .enhanced, .default]
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                let li = order.firstIndex(of: $0.quality) ?? 99
                let ri = order.firstIndex(of: $1.quality) ?? 99
                return li == ri ? $0.name < $1.name : li < ri
            }
            .map { VoiceOption(id: $0.identifier, name: $0.name, quality: $0.quality, language: $0.language) }
    }

    var selectedVoice: AVSpeechSynthesisVoice? {
        // Look up by full identifier first (new format)
        if !preferredVoiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: preferredVoiceIdentifier) {
            return voice
        }
        // Fallback: pick best available English voice
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return all.first(where: { $0.quality == .premium })
            ?? all.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - Private: Shared

    private var pausedAtTime        = 0.0
    private var currentChapterId    = ""
    private var currentBibleId      = ""
    private let anthropic           = AnthropicService()
    /// Set to true when a chapter ends naturally so the next openPlayer call auto-plays from 0.
    private var pendingAutoPlay     = false

    // MARK: - Private: Verse Tracking

    /// Approximate char-start of each verse in the cleaned (TTS) text.
    private var verseCharOffsets: [(number: String, startChar: Int)] = []

    private func buildVerseOffsets(from rawText: String) {
        var offsets: [(number: String, startChar: Int)] = []
        guard let pattern = try? NSRegularExpression(pattern: #"\[(\d+)\]\s*"#) else {
            verseCharOffsets = offsets; return
        }
        let nsRaw   = rawText as NSString
        let matches = pattern.matches(in: rawText, range: NSRange(location: 0, length: nsRaw.length))
        // Each "[N]\s*" (length L) is replaced by " " (length 1) → removes L-1 chars.
        var totalRemoved = 0
        for match in matches {
            let num       = nsRaw.substring(with: match.range(at: 1))
            let cleanedPos = max(0, match.range.location - totalRemoved)
            offsets.append((number: num, startChar: cleanedPos))
            totalRemoved  += match.range.length - 1
        }
        verseCharOffsets = offsets
    }

    // MARK: - Private: TTS

    private var synthesizer      = AVSpeechSynthesizer()
    private var progressTimer:   Timer?
    private var playStartDate:   Date?
    private var currentText      = ""      // cleaned text (no [N] markers) — used for TTS
    private var rawChapterText   = ""      // original text (with [N] markers) — passed to Claude
    private var ttsSpokenCount   = 0       // char count of the spoken TTS text (after [V:N] markers stripped)
    private let charsPerSecond:  Double = 6.5  // calibrated for half-default speech rate (0.25)

    // MARK: - Private: Streaming

    private let audioService      = AudioBibleService()
    private var avPlayer:         AVPlayer?
    private var timeObserver:     Any?
    private var playerObserver:   NSObjectProtocol?
    private var isStreamingMode   = false
    private var cachedAudioBibleId: String?   // first audio Bible that returned a valid URL
    private var confirmedNoAudio  = false     // true once we know the API has nothing

    // MARK: - Open / Change Chapter

    func openPlayer(for chapterId: String, text: String, bibleId: String = "", reference: String = "") {
        isVisible = true
        // Reload whenever the chapter OR the translation changes, so TTS always matches
        // the text on screen.  The text itself is always the authoritative check.
        guard chapterId != currentChapterId || bibleId != currentBibleId || currentText.isEmpty else { return }

        let wasPlaying    = isPlaying || pendingAutoPlay   // true if playing OR auto-advancing
        pendingAutoPlay   = false
        let prevChapterId = currentChapterId
        let prevBibleId   = currentBibleId
        stopEverything()
        currentChapterId  = chapterId
        currentBibleId    = bibleId
        // Each translation may have different audio availability — reset when switching.
        if bibleId != prevBibleId { confirmedNoAudio = false; cachedAudioBibleId = nil }
        currentReference  = reference
        rawChapterText    = text
        buildVerseOffsets(from: text)             // must run before cleanText strips markers
        currentText       = cleanText(text)
        ttsSpokenCount    = currentText.count     // preliminary; playTTS will refine from reformatted text
        duration          = Double(currentText.count) / (charsPerSecond * Double(playbackRate))

        let isChapterChange = chapterId != prevChapterId || bibleId != prevBibleId
        if wasPlaying || isChapterChange {
            // Chapter switched (or was auto-advancing) → always start from the very beginning.
            pausedAtTime = 0
            currentTime  = 0
        } else {
            // Same chapter reopened while paused → restore where the user left off.
            let saved = UserDefaults.standard.double(forKey: posKey(chapterId))
            pausedAtTime = min(saved, max(0, duration - 1))
            currentTime  = pausedAtTime
        }

        // Try to get real streaming audio in the background.
        // TTS is ready immediately as a fallback.
        if !bibleId.isEmpty {
            audioSource = "Checking API…"
            Task { await tryStreamingAudio(bibleId: bibleId, chapterId: chapterId) }
        } else {
            audioSource = "Text-to-Speech"
        }

        if wasPlaying { play() }
    }

    func updateText(_ text: String, for chapterId: String) {
        guard chapterId == currentChapterId else { return }
        rawChapterText = text
        buildVerseOffsets(from: text)
        currentText = cleanText(text)
        if !isStreamingMode {
            duration = Double(currentText.count) / (charsPerSecond * Double(playbackRate))
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

    /// Stops audio immediately but signals that the next chapter should auto-play.
    /// Used during chapter transitions so the new chapter picks up playback.
    func pauseForChapterChange() {
        guard isPlaying else { return }
        pause()
        pendingAutoPlay = true
    }

    func skip(_ seconds: Double) {
        seek(to: max(0, min(duration, currentTime + seconds)))
    }

    /// Seeks to the verse immediately before the currently playing one.
    /// If already at the first verse, seeks to its beginning.
    func skipToPreviousVerse() {
        guard !verseCharOffsets.isEmpty else { return }
        if let idx = verseCharOffsets.firstIndex(where: { $0.number == currentVerseNumber }) {
            let target = verseCharOffsets[max(0, idx - 1)]
            seekToVerse(target.number)
        } else {
            seek(to: 0)
        }
    }

    /// Seeks to the verse immediately after the currently playing one.
    /// No-op if already at the last verse.
    func skipToNextVerse() {
        guard !verseCharOffsets.isEmpty else { return }
        if let idx = verseCharOffsets.firstIndex(where: { $0.number == currentVerseNumber }) {
            let nextIdx = idx + 1
            guard nextIdx < verseCharOffsets.count else { return }
            seekToVerse(verseCharOffsets[nextIdx].number)
        } else {
            seekToVerse(verseCharOffsets[0].number)
        }
    }

    /// Seeks playback to the start of the given verse number.
    /// No-op if the verse is not found or the player is not loaded.
    func seekToVerse(_ verseNumber: String) {
        guard !verseCharOffsets.isEmpty, duration > 0,
              let entry = verseCharOffsets.first(where: { $0.number == verseNumber }) else { return }
        // verseCharOffsets are in spoken-text space for TTS, currentText space for streaming.
        let spaceSize  = isStreamingMode ? currentText.count : ttsSpokenCount
        let ratio      = Double(entry.startChar) / Double(max(spaceSize, 1))
        let targetTime = ratio * duration
        seek(to: min(targetTime, duration - 0.1))
    }

    func seek(to time: Double) {
        pausedAtTime = time
        currentTime  = time
        updateVerseFromTime(time)   // update verse marker immediately on scrub
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

    /// Computes which verse corresponds to a given playback time and updates currentVerseNumber.
    private func updateVerseFromTime(_ time: Double) {
        guard !verseCharOffsets.isEmpty, duration > 0 else { return }
        let ratio = min(time / duration, 1.0)
        if isStreamingMode {
            // Streaming: proportional index into verse list
            let idx = min(Int(ratio * Double(verseCharOffsets.count)), verseCharOffsets.count - 1)
            currentVerseNumber = verseCharOffsets[idx].number
        } else {
            // TTS: proportional position in spoken-text space (verseCharOffsets rebuilt from reformatted text)
            let cleanChar = Int(ratio * Double(ttsSpokenCount))
            currentVerseNumber = verseCharOffsets.last(where: { $0.startChar <= cleanChar })?.number ?? ""
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

            // Only use audio Bibles linked to the current text translation.
            // Falling back to arbitrary English audio would play a DIFFERENT translation,
            // which won't match the text on screen. TTS is always the correct fallback.
            var candidates: [AudioBible] = []
            if !bibleId.isEmpty {
                candidates = (try? await audioService.fetchAudioBibles(bibleId: bibleId)) ?? []
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
                // Proportional verse tracking for streaming (no server-side timing data)
                if self.duration > 0, !self.verseCharOffsets.isEmpty {
                    let ratio = self.currentTime / self.duration
                    let idx   = min(
                        Int(ratio * Double(self.verseCharOffsets.count)),
                        self.verseCharOffsets.count - 1
                    )
                    let verse = self.verseCharOffsets[idx].number
                    if verse != self.currentVerseNumber { self.currentVerseNumber = verse }
                }
            }
        }

        // Detect when the chapter finishes playing — advance to next chapter.
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleChapterEnd()
            }
        }
    }

    private func playStreaming() {
        guard let player = avPlayer else { return }
        if pausedAtTime > 0 {
            let target = CMTime(seconds: pausedAtTime, preferredTimescale: 600)
            player.seek(to: target) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.avPlayer?.play()
                    self.avPlayer?.rate = self.playbackRate
                    self.isPlaying = true
                }
            }
        } else {
            player.play()
            player.rate = playbackRate
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

        // v9: half-speed speech rate (0.5 × default); chapter title spoken first with 2 s pause;
        //     heading pause 2 s; verse-1 has no pre-pause (heading gap covers it).
        // Stored WITH markers so the cache can rebuild accurate verse offsets on reload.
        let cacheKey = "ttsReformatted_v9_\(currentBibleId)_\(currentChapterId)"

        // Cache hit: stored WITH [V:N] markers — strip them now to rebuild offsets + get spoken text.
        if let cachedWithMarkers = UserDefaults.standard.string(forKey: cacheKey) {
            let (spoken, offsets) = stripVerseMarkers(cachedWithMarkers)
            if !offsets.isEmpty { verseCharOffsets = offsets }
            ttsSpokenCount = spoken.count
            duration = Double(spoken.count) / (charsPerSecond * Double(playbackRate)) + sentencePauseTime(spoken)
            speakText(spoken)
            return
        }

        // Build text for Claude:
        //   Prepend chapter title ("Habakkuk 1.") + 25-newline pause (≈ 2 s).
        //   [§] headings → heading text + period + 25-newline pause (≈ 2 s).
        //   [1] verse 1 → [V:1] + 2 newlines (no pre-pause; heading gap already provides it).
        //   [N≥2] other verses → 12-newline pre-pause + [V:N] + 2 newlines (≈ 1.6 s gap).
        let textForClaude: String = {
            // Prefix: chapter title + 2 s pause before the chapter body.
            var t = "\(currentReference).\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n" + rawChapterText
            // Step 1: "[§] HEADING [N]…" → "HEADING.\n×25" (≈ 2 s gap).
            if let r = try? NSRegularExpression(
                pattern: #"\[§\]\s*(.*?)\s*(?=\[\d+\]|\[§\])"#,
                options: [.dotMatchesLineSeparators]
            ) {
                t = r.stringByReplacingMatches(
                    in: t, range: NSRange(t.startIndex..., in: t),
                    withTemplate: "$1.\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"
                )
            }
            // Step 2: any leftover [§] (heading at end of text, no verse follows)
            if let r = try? NSRegularExpression(pattern: #"\[§\]\s*"#) {
                t = r.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
            }
            // Step 3a: verse 1 → [V:1] + 2 newlines (no pre-pause; chapter title/heading gap is enough).
            if let r = try? NSRegularExpression(pattern: #"\[1\]\s*"#) {
                t = r.stringByReplacingMatches(
                    in: t, range: NSRange(t.startIndex..., in: t),
                    withTemplate: "[V:1]\n\n"
                )
            }
            // Step 3b: all other verse markers → 12-newline pre-pause + [V:N] + 2 newlines (≈ 1.6 s).
            // [V:N] is preserved by Claude (rule 5) and stripped before speaking.
            if let r = try? NSRegularExpression(pattern: #"\[(\d+)\]\s*"#) {
                t = r.stringByReplacingMatches(
                    in: t, range: NSRange(t.startIndex..., in: t),
                    withTemplate: "\n\n\n\n\n\n\n\n\n\n\n\n[V:$1]\n\n"
                )
            }
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        // Call Claude to add natural punctuation pauses while preserving [V:N] markers.
        isPreparingTTS = true
        let reference = currentReference
        let chapterId = currentChapterId

        Task {
            let reformatted = await anthropic.reformatForTTS(text: textForClaude, reference: reference)

            // Parse [V:N] markers from Claude's output to build accurate verse offsets
            // in spoken-text space, then strip them before speaking.
            let (spoken, parsedOffsets) = stripVerseMarkers(reformatted)
            if !parsedOffsets.isEmpty { verseCharOffsets = parsedOffsets }

            // Cache with markers intact so future loads can also rebuild offsets accurately.
            UserDefaults.standard.set(reformatted, forKey: cacheKey)

            guard currentChapterId == chapterId else {
                isPreparingTTS = false
                return
            }
            ttsSpokenCount = spoken.count
            duration       = Double(spoken.count) / (charsPerSecond * Double(playbackRate)) + sentencePauseTime(spoken)
            isPreparingTTS = false
            speakText(spoken)
        }
    }

    /// Strips `[V:N]` synchronization markers from the text, returning both
    /// the speakable text and verse char offsets relative to that stripped text.
    private func stripVerseMarkers(_ text: String) -> (spoken: String, offsets: [(number: String, startChar: Int)]) {
        var offsets: [(number: String, startChar: Int)] = []
        guard let rx = try? NSRegularExpression(pattern: #"\[V:(\d+)\]"#) else {
            return (text, offsets)
        }
        let ns      = text as NSString
        let matches = rx.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var stripped = 0
        for m in matches {
            let num = ns.substring(with: m.range(at: 1))
            offsets.append((number: num, startChar: m.range.location - stripped))
            stripped += m.range.length
        }
        let spoken = rx.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: ""
        )
        return (spoken, offsets)
    }

    private func speakText(_ text: String) {
        let charPos  = max(0, min(Int(pausedAtTime * charsPerSecond), text.count - 1))
        let startIdx = text.index(text.startIndex, offsetBy: charPos)
        let slice    = String(text[startIdx...])
        guard !slice.isEmpty else { return }

        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        synthesizer.stopSpeaking(at: .immediate)

        // Split into sentences so the synthesizer applies natural sentence-ending
        // intonation (slight pitch drop) at each period, plus a brief breath pause.
        let sentences = splitIntoSentences(slice)
        let voice     = selectedVoice
        let rate      = AVSpeechUtteranceDefaultSpeechRate * 0.5 * playbackRate

        for (i, sentence) in sentences.enumerated() {
            let utterance   = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            utterance.rate  = rate
            // Small pause after each sentence (except the last) for natural rhythm.
            if i < sentences.count - 1 {
                utterance.postUtteranceDelay = 0.25
            }
            synthesizer.speak(utterance)
        }

        isPlaying     = true
        playStartDate = Date()
        startProgressTimer(from: pausedAtTime)
    }

    /// Estimates total sentence-boundary pause time for a given text (0.25 s per boundary).
    private func sentencePauseTime(_ text: String) -> Double {
        let count = splitIntoSentences(text).count
        return count > 1 ? Double(count - 1) * 0.25 : 0
    }

    /// Splits text into sentence-sized chunks, keeping the terminating punctuation
    /// attached. Falls back to the full text if no sentence boundaries are found.
    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: .bySentences
        ) { sub, _, _, _ in
            if let s = sub {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
            }
        }
        return sentences.isEmpty ? [text] : sentences
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

                // Proportional verse tracking: ratio × spoken-text length → char position.
                // verseCharOffsets are now in spoken-text space (rebuilt from reformatted text)
                // so this ratio correctly maps elapsed time to the current verse.
                if !self.verseCharOffsets.isEmpty, self.duration > 0, self.ttsSpokenCount > 0 {
                    let ratio     = min(newTime / self.duration, 1.0)
                    let cleanChar = Int(ratio * Double(self.ttsSpokenCount))
                    let verse     = self.verseCharOffsets.last(where: { $0.startChar <= cleanChar })?.number ?? ""
                    if verse != self.currentVerseNumber { self.currentVerseNumber = verse }
                }

                if !self.synthesizer.isSpeaking && !self.synthesizer.isPaused {
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                    self.handleChapterEnd()
                }
            }
        }
    }

    // MARK: - Stop Everything

    /// Called when a chapter finishes playing to the end (not when the user stops manually).
    /// Resets state and signals ReaderView to advance to the next chapter.
    private func handleChapterEnd() {
        let finishedChapter = currentChapterId
        isPlaying           = false
        currentTime         = 0
        pausedAtTime        = 0
        currentVerseNumber  = ""
        UserDefaults.standard.removeObject(forKey: posKey(finishedChapter))
        // Tell the next openPlayer call to auto-play from 0 (audiobook flow).
        pendingAutoPlay  = true
        chapterDidFinish = true
    }

    private func stopEverything() {
        synthesizer.stopSpeaking(at: .immediate)
        progressTimer?.invalidate()
        progressTimer      = nil
        cleanupAVPlayer()
        isPlaying          = false
        isSeeking          = false
        currentTime        = 0
        pausedAtTime       = 0
        currentVerseNumber = ""
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
