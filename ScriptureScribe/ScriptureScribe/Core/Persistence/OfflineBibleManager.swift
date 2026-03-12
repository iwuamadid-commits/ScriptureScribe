//
//  OfflineBibleManager.swift
//  ScriptureScribe
//
//  Manages downloading and deleting offline Bible translations
//  from Firebase Storage. Tracks download state for the UI.
//

import Foundation
import Combine
import FirebaseStorage

// MARK: - Download State

enum OfflineDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded(size: String)
    case failed(String)

    static func == (lhs: OfflineDownloadState, rhs: OfflineDownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded): return true
        case (.downloading(let a), .downloading(let b)): return a == b
        case (.downloaded(let a), .downloaded(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Manager

final class OfflineBibleManager: ObservableObject {

    @Published var downloadStates: [String: OfflineDownloadState] = [:]

    private let store = OfflineBibleStore()

    init() {
        refreshStates()
    }

    // MARK: - State Refresh

    /// Check disk for already-downloaded translations and update states.
    func refreshStates() {
        for info in OfflineTranslationConfig.all {
            if store.isDownloaded(info.key) {
                let size = store.sizeOnDisk(info.key) ?? "Unknown"
                downloadStates[info.key] = .downloaded(size: size)
            } else {
                downloadStates[info.key] = .notDownloaded
            }
        }
    }

    // MARK: - Download

    @MainActor
    func download(translationKey key: String) async {
        guard let config = OfflineTranslationConfig.info(forKey: key) else { return }

        downloadStates[key] = .downloading(progress: 0)

        do {
            // 1. Download from Firebase Storage to a temp file
            let ref = Storage.storage().reference().child(config.firebasePath)
            print("📥 Starting download: \(config.firebasePath)")
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(key)_\(UUID().uuidString).json.gz")

            // Use write(toFile:) with a progress observer
            let downloadTask = ref.write(toFile: tempURL)

            // Observe progress on main actor
            let progressHandle = downloadTask.observe(.progress) { [weak self] snapshot in
                guard let progress = snapshot.progress else { return }
                let fraction = Double(progress.completedUnitCount) / max(Double(progress.totalUnitCount), 1)
                Task { @MainActor in
                    self?.downloadStates[key] = .downloading(progress: fraction)
                }
            }

            // Await completion
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                downloadTask.observe(.success) { _ in
                    print("✅ Firebase download succeeded for \(key)")
                    cont.resume(returning: tempURL)
                }
                downloadTask.observe(.failure) { snapshot in
                    print("❌ Firebase download failed for \(key): \(snapshot.error?.localizedDescription ?? "unknown")")
                    cont.resume(throwing: snapshot.error ?? NSError(domain: "OfflineBibleManager", code: -1,
                                                                     userInfo: [NSLocalizedDescriptionKey: "Download failed"]))
                }
            }

            downloadTask.removeObserver(withHandle: progressHandle)

            // 2. Read and decompress (gzip format)
            let compressedData = try Data(contentsOf: tempURL)
            print("📦 Downloaded \(compressedData.count) bytes, first bytes: \(Array(compressedData.prefix(4)))")
            let jsonData: Data
            // Check for gzip magic bytes (1f 8b)
            if compressedData.count >= 2 && compressedData[0] == 0x1f && compressedData[1] == 0x8b {
                print("🗜️ Decompressing gzip data...")
                jsonData = try Self.gunzip(compressedData)
            } else {
                print("📄 Data is not gzipped, using as-is")
                jsonData = compressedData
            }
            print("📄 JSON data: \(jsonData.count) bytes")

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            // 3. Decode
            let decoder = JSONDecoder()
            let package = try decoder.decode(OfflineBiblePackage.self, from: jsonData)
            print("📖 Decoded: \(package.metadata.translationKey) — \(package.chapters.count) chapters")

            // 4. Write to disk
            try store.save(metadata: package.metadata, chapters: package.chapters)

            // 5. Update state
            let size = store.sizeOnDisk(key) ?? "Unknown"
            downloadStates[key] = .downloaded(size: size)
            print("✅ Offline \(key) ready — \(size)")

        } catch {
            print("❌ Offline download failed for \(key): \(error)")
            downloadStates[key] = .failed(error.localizedDescription)
            // Clean up any partial download
            store.delete(translationKey: key)
        }
    }

    // MARK: - Delete

    @MainActor
    func delete(translationKey key: String) {
        store.delete(translationKey: key)
        downloadStates[key] = .notDownloaded
    }

    // MARK: - Helpers

    func state(forBibleId id: String) -> OfflineDownloadState {
        guard let config = OfflineTranslationConfig.info(forBibleId: id) else { return .notDownloaded }
        return downloadStates[config.key] ?? .notDownloaded
    }

    func isOfflineCapable(bibleId: String) -> Bool {
        OfflineTranslationConfig.offlineBibleIds.contains(bibleId)
    }

    // MARK: - Gzip Decompression

    /// Decompress gzip data using zlib via the Compression framework.
    private static func gunzip(_ data: Data) throws -> Data {
        // Skip gzip header (10 bytes minimum) and use raw deflate decompression
        // Gzip: [1f 8b] [08] [flags] [4 bytes mtime] [xfl] [os] ... deflate data ... [crc32] [size]
        guard data.count >= 10 else {
            throw NSError(domain: "OfflineBibleManager", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid gzip data"])
        }

        var offset = 10
        let flags = data[3]

        // FEXTRA (bit 2)
        if flags & 0x04 != 0 && offset + 2 <= data.count {
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        // FNAME (bit 3) — null-terminated string
        if flags & 0x08 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FCOMMENT (bit 4) — null-terminated string
        if flags & 0x10 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FHCRC (bit 1)
        if flags & 0x02 != 0 { offset += 2 }

        // Strip the 8-byte gzip trailer (CRC32 + ISIZE)
        let deflateData = data[offset ..< (data.count - 8)]

        // Decompress raw deflate using NSData
        let nsData = deflateData as NSData
        let decompressed = try nsData.decompressed(using: .zlib) as Data
        return decompressed
    }
}

// MARK: - Package Format (what's in the .json.gz file)

/// The top-level structure of the downloaded JSON archive.
struct OfflineBiblePackage: Codable {
    let metadata: OfflineBibleMetadata
    let chapters: [OfflineChapterFile]
}
