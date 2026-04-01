import Foundation
import GRDB

struct Fragment: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "fragments"

    var id: Int64?
    var content: String
    var contentHash: String
    var focusedText: String?
    var bundleIdentifier: String
    var appName: String
    var windowTitle: String?
    var url: String?
    var appCategory: String?
    var capturedAt: Int         // Unix timestamp
    var day: String             // "YYYY-MM-DD"
    var wordCount: Int
    var summary: String?
    var imagePath: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Column mappings

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let content = Column(CodingKeys.content)
        static let contentHash = Column(CodingKeys.contentHash)
        static let focusedText = Column(CodingKeys.focusedText)
        static let bundleIdentifier = Column(CodingKeys.bundleIdentifier)
        static let appName = Column(CodingKeys.appName)
        static let windowTitle = Column(CodingKeys.windowTitle)
        static let url = Column(CodingKeys.url)
        static let appCategory = Column(CodingKeys.appCategory)
        static let capturedAt = Column(CodingKeys.capturedAt)
        static let day = Column(CodingKeys.day)
        static let wordCount = Column(CodingKeys.wordCount)
        static let summary = Column(CodingKeys.summary)
        static let imagePath = Column(CodingKeys.imagePath)
    }
}

// MARK: - Search Result

struct FragmentSearchResult: Sendable {
    let fragment: Fragment
    let snippet: String
    let rank: Double
}

// MARK: - App Summary (for browse view)

struct AppSummary: Sendable, Identifiable {
    var id: String { bundleIdentifier }
    let appName: String
    let bundleIdentifier: String
    let count: Int
    let lastCaptured: Int
}

// MARK: - Helper

extension Fragment {
    static func makeDay(from date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var relativeTime: String {
        let now = Int(Date().timeIntervalSince1970)
        let diff = now - capturedAt
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(diff / 60)m ago" }
        if diff < 86400 { return "\(diff / 3600)h ago" }
        let days = diff / 86400
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }

    var appIcon: String {
        switch appCategory {
        case "code": return "chevronleft.forwardslash.chevronright"
        case "browsing": return "globe"
        case "communication": return "bubble.left.fill"
        case "email": return "envelope.fill"
        case "design": return "paintbrush.fill"
        case "work": return "briefcase.fill"
        default: return "app.fill"
        }
    }
}
