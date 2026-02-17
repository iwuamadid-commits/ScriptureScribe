//
//  BibleAPIService.swift
//  ScriptureScribe
//
//  All communication with the API.Bible servers lives here.
//  Every method is async — it goes off to the internet, waits for a reply, then returns the data.
//  Results are cached in memory so we don't re-fetch the same data repeatedly.
//

import Foundation

final class BibleAPIService {

    // MARK: - In-Memory Cache

    private var translationsCache: [BibleTranslation]?
    private var booksCache:    [String: [BibleBook]]    = [:]  // key = bibleId
    private var chaptersCache: [String: [BibleChapter]] = [:]  // key = "bibleId/bookId"

    // MARK: - Fetch All Translations

    /// Returns the full list of Bible translations your API key has access to (1,500+).
    /// English translations are sorted to the top; the rest follow alphabetically by language.
    func fetchTranslations() async throws -> [BibleTranslation] {
        if let cached = translationsCache { return cached }

        let url = try apiURL(path: "/bibles")
        let response: ListResponse<BibleTranslation> = try await fetch(url)

        let sorted = response.data.sorted { lhs, rhs in
            if lhs.isEnglish != rhs.isEnglish { return lhs.isEnglish }
            if lhs.language.name != rhs.language.name { return lhs.language.name < rhs.language.name }
            return lhs.name < rhs.name
        }

        translationsCache = sorted
        return sorted
    }

    // MARK: - Fetch Books

    /// Returns all books available in a given translation (66 for most Protestant Bibles).
    func fetchBooks(bibleId: String) async throws -> [BibleBook] {
        if let cached = booksCache[bibleId] { return cached }

        let url = try apiURL(path: "/bibles/\(bibleId)/books")
        let response: ListResponse<BibleBook> = try await fetch(url)
        booksCache[bibleId] = response.data
        return response.data
    }

    // MARK: - Fetch Chapters

    /// Returns all chapters in a given book (e.g. 50 chapters for Genesis).
    func fetchChapters(bibleId: String, bookId: String) async throws -> [BibleChapter] {
        let cacheKey = "\(bibleId)/\(bookId)"
        if let cached = chaptersCache[cacheKey] { return cached }

        let url = try apiURL(path: "/bibles/\(bibleId)/books/\(bookId)/chapters")
        let response: ListResponse<BibleChapter> = try await fetch(url)

        // Some translations include an "intro" chapter — filter it out so only numbered chapters show.
        let numbered = response.data.filter { $0.number.lowercased() != "intro" }
        chaptersCache[cacheKey] = numbered
        return numbered
    }

    // MARK: - Fetch Chapter Content

    /// Downloads and returns the full readable text for a single chapter.
    func fetchChapterContent(bibleId: String, chapterId: String) async throws -> BibleChapterContent {
        var components = URLComponents(string: AppConfig.bibleAPIBaseURL + "/bibles/\(bibleId)/chapters/\(chapterId)")!
        components.queryItems = [
            URLQueryItem(name: "content-type",           value: "text"),
            URLQueryItem(name: "include-notes",          value: "false"),
            URLQueryItem(name: "include-titles",         value: "true"),
            URLQueryItem(name: "include-chapter-numbers",value: "false"),
            URLQueryItem(name: "include-verse-numbers",  value: "true"),
            URLQueryItem(name: "include-verse-spans",    value: "false"),
        ]
        guard let url = components.url else { throw APIError.invalidURL }

        let response: DetailResponse<ChapterData> = try await fetch(url)
        let d = response.data
        return BibleChapterContent(
            id:          d.id,
            bibleId:     d.bibleId,
            bookId:      d.bookId,
            number:      d.number,
            reference:   d.reference,
            textContent: d.content ?? "No content available for this chapter.",
            copyright:   d.copyright ?? ""
        )
    }

    // MARK: - Search  (wired up fully in Phase 4)

    func search(bibleId: String, query: String) async throws -> [SearchResult] {
        // Phase 4 implementation placeholder — returns empty for now.
        return []
    }

    // MARK: - Private Helpers

    private func apiURL(path: String) throws -> URL {
        guard let url = URL(string: AppConfig.bibleAPIBaseURL + path) else {
            throw APIError.invalidURL
        }
        return url
    }

    /// Generic fetch: builds the request, sends it, checks for errors, decodes the JSON.
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
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case rateLimited
    case serverError(Int)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Couldn't build the request URL."
        case .invalidResponse:     return "Received an unexpected response from the server."
        case .unauthorized:        return "API key rejected. Check Secrets.xcconfig."
        case .notFound:            return "That content wasn't found."
        case .rateLimited:         return "Too many requests — please wait a moment before continuing."
        case .serverError(let c):  return "Server error (\(c)). Please try again."
        case .decodingFailed:      return "The server sent data in an unexpected format."
        }
    }
}

// MARK: - Private Codable Wrappers
// API.Bible wraps every response in {"data": ...}

private struct ListResponse<T: Codable>: Codable {
    let data: [T]
}

private struct DetailResponse<T: Codable>: Codable {
    let data: T
}

private struct ChapterData: Codable {
    let id:        String
    let bibleId:   String
    let bookId:    String
    let number:    String
    let reference: String
    let content:   String?   // plain text of the chapter
    let copyright: String?
}

// MARK: - Search Result (used in Phase 4)

struct SearchResult: Identifiable, Codable {
    let id:        String
    let reference: String
    let text:      String
}
