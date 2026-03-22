//
//  AudioBibleService.swift
//  ScriptureScribe
//
//  Talks to the API.Bible audio endpoints.
//  • fetchAudioBibles(bibleId:)  — lists audio Bibles linked to the current text Bible
//  • fetchChapterURL(…)          — returns the signed MP3 URL for one chapter
//

import Foundation

@MainActor
final class AudioBibleService {

    // MARK: - Cache (keyed by bibleId so different translations cache separately)

    private var audioBiblesCache: [String: [AudioBible]] = [:]

    // MARK: - Fetch Audio Bibles for a Text Bible

    /// Returns audio Bibles that correspond to the given text Bible ID.
    /// Passing an empty bibleId returns all audio Bibles the API key can access.
    func fetchAudioBibles(bibleId: String = "") async throws -> [AudioBible] {
        let cacheKey = bibleId.isEmpty ? "__all__" : bibleId
        if let cached = audioBiblesCache[cacheKey] { return cached }

        guard var components = URLComponents(string: AppConfig.bibleAPIBaseURL + "/audio-bibles")
        else { throw APIError.invalidURL }
        if !bibleId.isEmpty {
            components.queryItems = [URLQueryItem(name: "bibleId", value: bibleId)]
        }
        guard let url = components.url else { throw APIError.invalidURL }

        let response: ListResponse<AudioBible> = try await fetch(url)
        let sorted = response.data.sorted { lhs, rhs in
            if lhs.isEnglish != rhs.isEnglish { return lhs.isEnglish }
            return lhs.name < rhs.name
        }

        audioBiblesCache[cacheKey] = sorted
        return sorted
    }

    // MARK: - Fetch Chapter Streaming URL

    /// Returns the signed MP3 streaming URL for a single chapter.
    /// `chapterId` uses the same format as the text API — e.g. "GEN.1", "JHN.3".
    func fetchChapterURL(audioBibleId: String, chapterId: String) async throws -> String {
        let url = try apiURL(path: "/audio-bibles/\(audioBibleId)/chapters/\(chapterId)")
        let response: DetailResponse<AudioChapterDetail> = try await fetch(url)

        guard let resourceUrl = response.data.resourceUrl, !resourceUrl.isEmpty else {
            throw APIError.notFound
        }
        return resourceUrl
    }

    // MARK: - Private Helpers

    private func apiURL(path: String) throws -> URL {
        guard let url = URL(string: AppConfig.bibleAPIBaseURL + path) else {
            throw APIError.invalidURL
        }
        return url
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(AppConfig.bibleAPIKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200: break
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        case 429: throw APIError.rateLimited
        default:  throw APIError.serverError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    // MARK: - Private Codable Wrappers

    private struct ListResponse<T: Codable>: Codable {
        let data: [T]
    }

    private struct DetailResponse<T: Codable>: Codable {
        let data: T
    }
}
