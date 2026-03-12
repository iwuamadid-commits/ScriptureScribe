//
//  OfflineBibleStore.swift
//  ScriptureScribe
//
//  Reads and writes offline Bible data to the Documents directory.
//
//  Disk layout per translation:
//    Documents/OfflineBibles/KJV/
//        metadata.json
//        chapters/GEN.1.json
//        chapters/GEN.2.json
//        ...
//        chapters/REV.22.json
//

import Foundation

// MARK: - Codable Models (disk format)

struct OfflineBibleMetadata: Codable {
    let translationKey: String       // "KJV"
    let apiBibleId:     String       // "de4e12af7f28f599-02"
    let name:           String
    let abbreviation:   String
    let copyright:      String
    let books:          [OfflineBookInfo]
}

struct OfflineBookInfo: Codable {
    let id:           String         // "GEN"
    let name:         String         // "Genesis"
    let nameLong:     String
    let abbreviation: String
    let chapterIds:   [String]       // ["GEN.1", "GEN.2", ...]
}

struct OfflineChapterFile: Codable {
    let id:        String            // "GEN.1"
    let bookId:    String
    let number:    String
    let reference: String
    let copyright: String
    let verses:    [CodableVerse]
}

struct CodableVerse: Codable {
    let number:   String
    let segments: [CodableSegment]
}

struct CodableSegment: Codable {
    let text:        String
    let isRedLetter: Bool
}

// MARK: - OfflineBibleStore

final class OfflineBibleStore {

    // MARK: - Directory Helpers

    private var baseDirURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineBibles", isDirectory: true)
    }

    private func translationDir(_ key: String) -> URL {
        baseDirURL.appendingPathComponent(key, isDirectory: true)
    }

    private func metadataURL(_ key: String) -> URL {
        translationDir(key).appendingPathComponent("metadata.json")
    }

    private func chaptersDir(_ key: String) -> URL {
        translationDir(key).appendingPathComponent("chapters", isDirectory: true)
    }

    private func chapterFileURL(_ key: String, chapterId: String) -> URL {
        let safeId = chapterId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        return chaptersDir(key).appendingPathComponent("\(safeId).json")
    }

    // MARK: - Query

    func isDownloaded(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: metadataURL(key).path)
    }

    /// Returns the total size of the translation directory as a human-readable string.
    func sizeOnDisk(_ key: String) -> String? {
        guard isDownloaded(key) else { return nil }
        let dir = translationDir(key)
        guard let enumerator = FileManager.default.enumerator(at: dir,
                                                               includingPropertiesForKeys: [.fileSizeKey],
                                                               options: [.skipsHiddenFiles]) else { return nil }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: total)
    }

    // MARK: - Read Metadata

    private func loadMetadata(_ key: String) -> OfflineBibleMetadata? {
        let url = metadataURL(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OfflineBibleMetadata.self, from: data)
    }

    // MARK: - Read Chapter Content

    func chapterContent(translationKey key: String, chapterId: String) -> BibleChapterContent? {
        let url = chapterFileURL(key, chapterId: chapterId)
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(OfflineChapterFile.self, from: data) else {
            return nil
        }
        return toBibleChapterContent(file, apiBibleId: OfflineTranslationConfig.info(forKey: key)?.apiBibleId ?? "")
    }

    // MARK: - Read Books / Chapters (from metadata)

    func books(translationKey key: String) -> [BibleBook]? {
        guard let meta = loadMetadata(key) else { return nil }
        return meta.books.map { bookInfo in
            BibleBook(id: bookInfo.id,
                      bibleId: meta.apiBibleId,
                      abbreviation: bookInfo.abbreviation,
                      name: bookInfo.name,
                      nameLong: bookInfo.nameLong)
        }
    }

    func chapters(translationKey key: String, bookId: String) -> [BibleChapter]? {
        guard let meta = loadMetadata(key),
              let bookInfo = meta.books.first(where: { $0.id == bookId }) else { return nil }
        return bookInfo.chapterIds.map { chapId in
            let num = chapId.components(separatedBy: ".").last ?? "1"
            return BibleChapter(id: chapId,
                                bibleId: meta.apiBibleId,
                                bookId: bookId,
                                number: num,
                                reference: "\(bookInfo.name) \(num)")
        }
    }

    // MARK: - Write

    func save(metadata: OfflineBibleMetadata, chapters: [OfflineChapterFile]) throws {
        let key = metadata.translationKey
        let fm = FileManager.default

        // Create directories
        let chapDir = chaptersDir(key)
        try fm.createDirectory(at: chapDir, withIntermediateDirectories: true)

        // Write metadata
        let metaData = try JSONEncoder().encode(metadata)
        try metaData.write(to: metadataURL(key), options: .atomic)

        // Write each chapter file
        let encoder = JSONEncoder()
        for chapter in chapters {
            let fileData = try encoder.encode(chapter)
            let url = chapterFileURL(key, chapterId: chapter.id)
            try fileData.write(to: url, options: .atomic)
        }
    }

    // MARK: - Delete

    func delete(translationKey key: String) {
        let dir = translationDir(key)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Conversion to App Models

    private func toBibleChapterContent(_ file: OfflineChapterFile, apiBibleId: String) -> BibleChapterContent {
        let parsedVerses = file.verses.map { v in
            ParsedVerse(
                number: v.number,
                segments: v.segments.map { s in
                    VerseSegment(text: s.text, isRedLetter: s.isRedLetter)
                }
            )
        }

        // Build [N] marker text for compatibility
        let textContent = file.verses.map { v in
            let text = v.segments.map(\.text).joined()
            return "[\(v.number)] \(text)"
        }.joined(separator: " ")

        return BibleChapterContent(
            id: file.id,
            bibleId: apiBibleId,
            bookId: file.bookId,
            number: file.number,
            reference: file.reference,
            textContent: textContent,
            copyright: file.copyright,
            parsedVerses: parsedVerses
        )
    }
}
