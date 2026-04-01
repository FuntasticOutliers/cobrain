import Foundation
import GRDB

struct PendingCapture: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pending_captures"

    var id: Int64?
    var imagePath: String
    var bundleIdentifier: String
    var appName: String
    var windowTitle: String?
    var url: String?
    var appCategory: String?
    var capturedAt: Int         // Unix timestamp
    var day: String             // "YYYY-MM-DD"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let capturedAt = Column(CodingKeys.capturedAt)
    }
}
