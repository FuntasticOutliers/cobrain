import Foundation
import CryptoKit
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "dedup")

final class DeduplicationService {
    static let shared = DeduplicationService()

    private var recentHashes: [(hash: String, bundleID: String, windowTitle: String?)] = []
    private let cacheSize = 200

    enum Result {
        case newFragment
        case duplicate
    }

    func check(content: String, bundleID: String, windowTitle: String?) -> Result {
        let hash = Self.hash(content)

        // Exact match in LRU → skip
        if recentHashes.contains(where: { $0.hash == hash }) {
            log.debug("Duplicate hash for \(bundleID)")
            return .duplicate
        }

        // Add to cache
        recentHashes.append((hash: hash, bundleID: bundleID, windowTitle: windowTitle))
        if recentHashes.count > cacheSize {
            recentHashes.removeFirst()
        }

        return .newFragment
    }

    static func hash(_ content: String) -> String {
        let normalized = normalize(content)
        let data = Data(normalized.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
