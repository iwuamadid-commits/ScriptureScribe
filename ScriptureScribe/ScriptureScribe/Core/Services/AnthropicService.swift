//
//  AnthropicService.swift
//  ScriptureScribe
//
//  Calls the Claude API (claude-haiku-4-5-20251001) to generate a unique
//  daily prayer, devotional, and reflection questions for a given Bible verse.
//
//  The API key lives in Secrets.xcconfig → Info.plist → AppConfig.anthropicAPIKey.
//  If the key is not configured, all calls throw AnthropicError.notConfigured
//  so the caller can fall back to local content gracefully.
//

import Foundation

// MARK: - Error

enum AnthropicError: Error, LocalizedError {
    case notConfigured
    case httpError(Int)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:          return "Anthropic API key not configured."
        case .httpError(let code):    return "Anthropic HTTP \(code)."
        case .parseFailed(let detail): return "Could not parse Claude response: \(detail)"
        }
    }
}

// MARK: - Service

struct AnthropicService {

    // MARK: - Public

    /// Generates a DailyEntry for the given verse and date.
    /// - Throws AnthropicError.notConfigured if no API key is set.
    func generateDailyEntry(
        verseId:        String,
        verseReference: String,
        date:           String      // "YYYY-MM-DD" — gives Claude seasonal context
    ) async throws -> DailyEntry {

        guard let apiKey = AppConfig.anthropicAPIKey else {
            throw AnthropicError.notConfigured
        }

        let prompt = buildPrompt(verseReference: verseReference, date: date)
        let responseText = try await callClaude(prompt: prompt, apiKey: apiKey)
        return try parse(responseText, verseId: verseId, verseReference: verseReference, date: date)
    }

    // MARK: - Verse Pool

    /// Picks today's verse ID deterministically from VersePool.json.
    /// Every device running on the same calendar day gets the same verse.
    static func verseIdForDate(_ date: Date = Date()) -> String {
        guard
            let url     = Bundle.main.url(forResource: "VersePool", withExtension: "json"),
            let data    = try? Data(contentsOf: url),
            let pool    = try? JSONDecoder().decode([String].self, from: data),
            !pool.isEmpty
        else {
            return "JHN.3.16"   // absolute fallback
        }
        let daysSinceEpoch = Int(date.timeIntervalSince1970 / 86400)
        return pool[abs(daysSinceEpoch) % pool.count]
    }

    // MARK: - Private helpers

    private func buildPrompt(verseReference: String, date: String) -> String {
        """
        You are a devotional writer for a Bible app called Scripture Scribe. \
        Generate a daily devotional for \(verseReference) for the date \(date).

        Return ONLY valid JSON. No markdown fences, no explanation, just the raw JSON object. Do not use em dashes anywhere in the output; use commas, periods, or semicolons instead:
        {
          "prayer": "A deeply personal 5–7 sentence prayer addressed directly to God, referencing the verse",
          "devotion": "A 2–3 paragraph devotional. Paragraph 1: historical/biblical context of the verse. Paragraph 2: deeper theological meaning. Paragraph 3: practical personal application for today. Separate paragraphs with a newline character (\\n\\n).",
          "affirmation": "A 2–3 sentence positive, faith-based daily affirmation grounded in the verse. Written in first person ('I am…', 'I trust…', 'God is…'). Personal, uplifting, and declarative.",
          "reflectionQuestions": [
            "A single thought-provoking reflection question that invites the reader to connect the verse to their own life"
          ]
        }
        """
    }

    private func callClaude(prompt: String, apiKey: String) async throws -> String {
        var request        = URLRequest(url: URL(string: AppConfig.anthropicBaseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey,            forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",      forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model":      "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AnthropicError.httpError(http.statusCode)
        }

        // Extract text from Claude's response envelope
        // Shape: { "content": [ { "type": "text", "text": "..." } ] }
        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first   = content.first,
            let text    = first["text"] as? String
        else {
            throw AnthropicError.parseFailed("unexpected envelope shape")
        }
        return text
    }

    private func parse(
        _ text: String,
        verseId: String,
        verseReference: String,
        date: String
    ) throws -> DailyEntry {

        // Strip any accidental markdown fences before decoding
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            let lines = clean.components(separatedBy: "\n")
            clean = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = clean.data(using: .utf8) else {
            throw AnthropicError.parseFailed("not UTF-8")
        }

        struct Payload: Decodable {
            let prayer:              String
            let devotion:            String
            let affirmation:         String?
            let reflectionQuestions: [String]
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return DailyEntry(
            date:                date,
            day:                 0,
            verseId:             verseId,
            verseReference:      verseReference,
            prayer:              payload.prayer,
            devotion:            payload.devotion,
            affirmation:         payload.affirmation ?? "",
            reflectionQuestions: payload.reflectionQuestions
        )
    }
}
