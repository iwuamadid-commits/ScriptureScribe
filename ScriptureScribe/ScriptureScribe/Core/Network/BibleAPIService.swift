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

    // MARK: - Disk Cache

    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BibleAPICache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Translations change rarely — cache for 7 days.
    private static let translationsTTL: TimeInterval = 7 * 24 * 3600
    /// Books and chapters never change — cache for 30 days.
    private static let structureTTL: TimeInterval = 30 * 24 * 3600

    private func diskCacheURL(for key: String) -> URL {
        Self.cacheDir.appendingPathComponent(key + ".json")
    }

    private func loadFromDisk<T: Decodable>(_ key: String, ttl: TimeInterval) -> T? {
        let url = diskCacheURL(for: key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < ttl,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func saveToDisk<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: diskCacheURL(for: key), options: .atomic)
    }

    // MARK: - Fetch All Translations

    /// Returns the full list of Bible translations your API key has access to (1,500+).
    /// English translations are sorted to the top; the rest follow alphabetically by language.
    func fetchTranslations() async throws -> [BibleTranslation] {
        if let cached = translationsCache { return cached }

        // Try disk cache first
        if let disk: [BibleTranslation] = loadFromDisk("translations", ttl: Self.translationsTTL) {
            translationsCache = disk
            return disk
        }

        let url = try apiURL(path: "/bibles")
        let response: ListResponse<BibleTranslation> = try await fetch(url)

        let sorted = response.data.sorted { lhs, rhs in
            if lhs.isEnglish != rhs.isEnglish { return lhs.isEnglish }
            if lhs.language.name != rhs.language.name { return lhs.language.name < rhs.language.name }
            return lhs.name < rhs.name
        }

        translationsCache = sorted
        saveToDisk(sorted, key: "translations")
        return sorted
    }

    // MARK: - Fetch Books

    /// Returns all books available in a given translation (66 for most Protestant Bibles).
    func fetchBooks(bibleId: String) async throws -> [BibleBook] {
        if let cached = booksCache[bibleId] { return cached }

        let diskKey = "books_\(bibleId)"
        if let disk: [BibleBook] = loadFromDisk(diskKey, ttl: Self.structureTTL) {
            booksCache[bibleId] = disk
            return disk
        }

        let url = try apiURL(path: "/bibles/\(bibleId)/books")
        let response: ListResponse<BibleBook> = try await fetch(url)
        booksCache[bibleId] = response.data
        saveToDisk(response.data, key: diskKey)
        return response.data
    }

    // MARK: - Fetch Chapters

    /// Returns all chapters in a given book (e.g. 50 chapters for Genesis).
    func fetchChapters(bibleId: String, bookId: String) async throws -> [BibleChapter] {
        let cacheKey = "\(bibleId)/\(bookId)"
        if let cached = chaptersCache[cacheKey] { return cached }

        let diskKey = "chapters_\(bibleId)_\(bookId)"
        if let disk: [BibleChapter] = loadFromDisk(diskKey, ttl: Self.structureTTL) {
            chaptersCache[cacheKey] = disk
            return disk
        }

        let url = try apiURL(path: "/bibles/\(bibleId)/books/\(bookId)/chapters")
        let response: ListResponse<BibleChapter> = try await fetch(url)

        // Some translations include an "intro" chapter — filter it out so only numbered chapters show.
        let numbered = response.data.filter { $0.number.lowercased() != "intro" }
        chaptersCache[cacheKey] = numbered
        saveToDisk(numbered, key: diskKey)
        return numbered
    }

    // MARK: - Fetch Chapter Content

    /// Downloads and returns the full readable text for a single chapter.
    /// HTML is requested so that Words of Jesus (red letter) markup is preserved.
    func fetchChapterContent(bibleId: String, chapterId: String) async throws -> BibleChapterContent {
        var components = URLComponents(string: AppConfig.bibleAPIBaseURL + "/bibles/\(bibleId)/chapters/\(chapterId)")!
        components.queryItems = [
            URLQueryItem(name: "content-type",           value: "html"),  // HTML preserves red-letter spans
            URLQueryItem(name: "include-notes",          value: "false"),
            URLQueryItem(name: "include-titles",         value: "true"),
            URLQueryItem(name: "include-chapter-numbers",value: "false"),
            URLQueryItem(name: "include-verse-numbers",  value: "true"),
            URLQueryItem(name: "include-verse-spans",    value: "false"),
        ]
        guard let url = components.url else { throw APIError.invalidURL }

        let response: DetailResponse<ChapterData> = try await fetch(url)
        let d = response.data
        let rawHTML = d.content ?? ""

        let (textContent, parsedVerses) = parseHTML(rawHTML)

        return BibleChapterContent(
            id:           d.id,
            bibleId:      d.bibleId,
            bookId:       d.bookId,
            number:       d.number,
            reference:    d.reference,
            textContent:  textContent.isEmpty ? "No content available for this chapter." : textContent,
            copyright:    d.copyright ?? "",
            parsedVerses: parsedVerses
        )
    }

    // MARK: - Fetch Single Verse

    /// Fetches the text of one verse (e.g. "JHN.3.16") for the given translation.
    /// Used by the Daily tab to display today's verse.
    func fetchVerse(bibleId: String, verseId: String) async throws -> DailyVerse {
        var components = URLComponents(
            string: AppConfig.bibleAPIBaseURL + "/bibles/\(bibleId)/verses/\(verseId)"
        )!
        components.queryItems = [
            URLQueryItem(name: "content-type",         value: "text"),
            URLQueryItem(name: "include-verse-numbers", value: "false"),
            URLQueryItem(name: "include-titles",        value: "false"),
        ]
        guard let url = components.url else { throw APIError.invalidURL }

        let response: DetailResponse<VerseData> = try await fetch(url)
        let d = response.data
        return DailyVerse(
            id:        d.id,
            reference: d.reference,
            text:      d.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    // MARK: - Search

    /// Searches the given translation for the query string and returns up to 20 matching verses.
    func search(bibleId: String, query: String, limit: Int = 20) async throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var components = URLComponents(
            string: AppConfig.bibleAPIBaseURL + "/bibles/\(bibleId)/search"
        )!
        components.queryItems = [
            URLQueryItem(name: "query",  value: query),
            URLQueryItem(name: "limit",  value: "\(limit)"),
            URLQueryItem(name: "sort",   value: "relevance"),
        ]
        guard let url = components.url else { throw APIError.invalidURL }

        let response: SearchAPIResponse = try await fetch(url)
        return response.data.verses
    }

    // MARK: - Private Helpers

    private func apiURL(path: String) throws -> URL {
        guard let url = URL(string: AppConfig.bibleAPIBaseURL + path) else {
            throw APIError.invalidURL
        }
        return url
    }

    // MARK: - HTML Parser (Red Letter Support)

    /// Converts API.Bible HTML into plain [N]-bracketed text AND a list of ParsedVerses.
    /// Tracks `<span class="wj">` (Words of Jesus) for red-letter coloring.
    private func parseHTML(_ html: String) -> (textContent: String, parsedVerses: [ParsedVerse]) {
        var verses:             [ParsedVerse]  = []
        var currentNum          = ""
        var currentSegments:    [VerseSegment] = []
        var currentBuffer       = ""
        var spanStack:          [String]       = []   // "wj", "v", or "" for other span types
        var inHeadingParagraph  = false
        var headingBuffer       = ""

        // Save accumulated text as a segment.
        // forceRedLetter: pass true when closing a "wj" span — the span was already
        // popped from the stack before this is called, so we can't rely on spanStack.
        func flushBuffer(forceRedLetter: Bool = false) {
            let isRL       = forceRedLetter || spanStack.contains("wj")
            let normalized = currentBuffer.replacingOccurrences(of: "\n", with: " ")
            let trimmed    = normalized.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { currentBuffer = ""; return }
            // Keep a trailing space so words at segment boundaries don't run together.
            let text = normalized.hasSuffix(" ") ? trimmed + " " : trimmed
            currentSegments.append(VerseSegment(text: text, isRedLetter: isRL))
            currentBuffer = ""
        }

        // Finalize the current verse and reset for the next.
        func flushVerse() {
            flushBuffer()
            guard !currentNum.isEmpty, !currentSegments.isEmpty else { return }
            verses.append(ParsedVerse(number: currentNum, segments: currentSegments))
            currentSegments = []
        }

        var i = html.startIndex
        while i < html.endIndex {
            let ch = html[i]

            if ch == "<" {
                guard let tagEnd = html[i...].firstIndex(of: ">") else { break }
                let rawTag = String(html[html.index(after: i)..<tagEnd])
                let lower  = rawTag.lowercased()

                if lower.hasPrefix("/span") {
                    let closed = spanStack.popLast() ?? ""
                    // Pass forceRedLetter:true because "wj" was just popped — spanStack
                    // no longer contains it when flushBuffer() runs.
                    if closed == "wj" { flushBuffer(forceRedLetter: true) }

                } else if lower.hasPrefix("span") {
                    // Use spanHasClass() to handle multiple CSS classes and both quote styles.
                    // e.g. class="wj add" or class='v label-style-normal' both match correctly.
                    if spanHasClass("wj", in: lower) {
                        flushBuffer()                      // save text so far as normal
                        spanStack.append("wj")
                    } else if spanHasClass("v", in: lower) || lower.contains("data-number=") {
                        flushVerse()                       // new verse — save previous
                        currentNum = extractDataNumber(from: rawTag) ?? extractDataNumber(from: lower) ?? ""
                        spanStack.append("v")
                    } else {
                        spanStack.append("")               // other span — ignore content
                    }
                } else if lower.hasPrefix("/p") {
                    if inHeadingParagraph {
                        // End of a section heading paragraph — save it as a special verse
                        // Drop leading punctuation (API sometimes includes a stray period)
                        var t = headingBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                        while t.first == "." || t.first == ":" { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
                        if !t.isEmpty {
                            verses.append(ParsedVerse(number: "§",
                                segments: [VerseSegment(text: t, isRedLetter: false)]))
                        }
                        inHeadingParagraph = false
                        headingBuffer      = ""
                    } else if spanStack.last != "v", !currentBuffer.hasSuffix(" ") {
                        currentBuffer += " "
                    }
                } else if lower.hasPrefix("p") {
                    // Detect USFM section-heading paragraph classes (s, s1, s2, ms, mr, d)
                    let headingClasses = ["s", "s1", "s2", "ms", "ms1", "mr", "d"]
                    if headingClasses.contains(where: { spanHasClass($0, in: lower) }) {
                        flushVerse()
                        inHeadingParagraph = true
                        headingBuffer      = ""
                    } else if !inHeadingParagraph, spanStack.last != "v",
                              !currentBuffer.hasSuffix(" ") {
                        currentBuffer += " "
                    }
                } else if lower.hasPrefix("br") {
                    if !inHeadingParagraph, spanStack.last != "v",
                       !currentBuffer.hasSuffix(" ") {
                        currentBuffer += " "
                    }
                }
                i = html.index(after: tagEnd)

            } else if ch == "&" {
                guard let semiEnd = html[i...].firstIndex(of: ";") else {
                    if spanStack.last != "v" { currentBuffer.append(ch) }
                    i = html.index(after: i)
                    continue
                }
                let entity = String(html[html.index(after: i)..<semiEnd])
                if inHeadingParagraph {
                    headingBuffer += decodeHTMLEntity(entity)
                } else if spanStack.last != "v" {
                    currentBuffer += decodeHTMLEntity(entity)
                }
                i = html.index(after: semiEnd)

            } else {
                if inHeadingParagraph {
                    headingBuffer.append(ch)
                } else if spanStack.last != "v" {
                    currentBuffer.append(ch)
                }
                i = html.index(after: i)
            }
        }
        flushVerse()   // finalize last verse

        // Rebuild plain text in [N] bracket format — compatible with BibleTextView.parseVerses()
        let textContent = verses.map { v in
            "[\(v.number)] " + v.segments.map(\.text).joined()
        }.joined(separator: " ")

        return (textContent, verses)
    }

    /// Returns true if a lowercased HTML tag string contains the given CSS class name.
    /// Correctly handles multiple classes (e.g. class="wj add") and both quote styles.
    private func spanHasClass(_ cls: String, in lowerTag: String) -> Bool {
        guard let classRange = lowerTag.range(of: "class=") else { return false }
        var rest = lowerTag[classRange.upperBound...]
        guard let q = rest.first, q == "\"" || q == "'" else { return false }
        rest = rest.dropFirst()
        guard let end = rest.firstIndex(of: q) else { return false }
        let classValue = String(rest[..<end])
        return classValue.components(separatedBy: .whitespaces).contains(cls)
    }

    /// Extracts the verse number from a `data-number` attribute. Handles both quote styles.
    private func extractDataNumber(from tag: String) -> String? {
        for needle in ["data-number=\"", "data-number='"] {
            if let r = tag.range(of: needle) {
                let rest = tag[r.upperBound...]
                let delimiter: Character = needle.hasSuffix("\"") ? "\"" : "'"
                if let q = rest.firstIndex(of: delimiter) {
                    let num = String(rest[..<q])
                    return num.isEmpty ? nil : num
                }
            }
        }
        return nil
    }

    /// Converts common HTML entities to their plain-text equivalents.
    private func decodeHTMLEntity(_ entity: String) -> String {
        switch entity {
        case "nbsp":   return " "
        case "amp":    return "&"
        case "lt":     return "<"
        case "gt":     return ">"
        case "quot":   return "\""
        case "apos":   return "'"
        case "mdash":  return "\u{2014}"
        case "ndash":  return "\u{2013}"
        case "ldquo":  return "\u{201C}"
        case "rdquo":  return "\u{201D}"
        case "lsquo":  return "\u{2018}"
        case "rsquo":  return "\u{2019}"
        case "hellip": return "\u{2026}"
        default:
            if entity.hasPrefix("#x"), let v = UInt32(entity.dropFirst(2), radix: 16),
               let s = Unicode.Scalar(v) { return String(Character(s)) }
            if entity.hasPrefix("#"), let v = UInt32(entity.dropFirst()),
               let s = Unicode.Scalar(v) { return String(Character(s)) }
            return "&\(entity);"   // unknown entity — return as-is
        }
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
        case .rateLimited:         return "Too many requests. Please wait a moment before continuing."
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

// API.Bible search wraps results in { "data": { "verses": [...] } }
private struct SearchAPIResponse: Codable {
    struct SearchData: Codable {
        let verses: [SearchResult]
    }
    let data: SearchData
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

private struct VerseData: Codable {
    let id:        String
    let reference: String
    let content:   String?
}

// MARK: - Search Result (used in Phase 4)

struct SearchResult: Identifiable, Codable {
    let id:        String
    let reference: String
    let text:      String
}

// MARK: - Daily Verse (used in Phase 5)

struct DailyVerse {
    let id:        String
    let reference: String
    let text:      String
}
