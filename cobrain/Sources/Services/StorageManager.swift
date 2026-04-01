import CoreGraphics
import Foundation
import GRDB
import ImageIO
import os
import UniformTypeIdentifiers

private let log = Logger(subsystem: "dev.cobrain.app", category: "storage")

final class StorageManager: @unchecked Sendable {
    static let shared = StorageManager()

    private let dbPool: DatabasePool

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("cobrain", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("brain.sqlite").path

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        dbPool = try! DatabasePool(path: dbPath, configuration: config)
        log.info("Database opened at \(dbPath)")
        try! migrate()
    }

    // MARK: - Migration

    private func migrate() throws {
        try dbPool.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS fragments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    content TEXT NOT NULL,
                    contentHash TEXT NOT NULL,
                    focusedText TEXT,
                    bundleIdentifier TEXT NOT NULL,
                    appName TEXT NOT NULL,
                    windowTitle TEXT,
                    url TEXT,
                    appCategory TEXT,
                    capturedAt INTEGER NOT NULL,
                    day TEXT NOT NULL,
                    wordCount INTEGER NOT NULL DEFAULT 0,
                    summary TEXT
                )
                """)

            // Migration: add summary column if missing
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(fragments)")
            let columnNames = columns.map { $0["name"] as String }
            if !columnNames.contains("summary") {
                try db.execute(sql: "ALTER TABLE fragments ADD COLUMN summary TEXT")
                log.info("Migrated: added summary column")
            }
            if !columnNames.contains("imagePath") {
                try db.execute(sql: "ALTER TABLE fragments ADD COLUMN imagePath TEXT")
                log.info("Migrated: added imagePath column")
            }

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_fragments_day ON fragments(day)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_fragments_captured_at ON fragments(capturedAt)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_fragments_content_hash ON fragments(contentHash)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_fragments_bundle ON fragments(bundleIdentifier)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_fragments_category ON fragments(appCategory)")

            // Pending captures queue (batch inference)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS pending_captures (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    imagePath TEXT NOT NULL,
                    bundleIdentifier TEXT NOT NULL,
                    appName TEXT NOT NULL,
                    windowTitle TEXT,
                    url TEXT,
                    appCategory TEXT,
                    capturedAt INTEGER NOT NULL,
                    day TEXT NOT NULL
                )
                """)

            // FTS5 virtual table
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS fragments_fts USING fts5(
                    content,
                    windowTitle,
                    appName,
                    url,
                    content='fragments',
                    content_rowid='id',
                    tokenize='porter unicode61'
                )
                """)

            // Sync triggers
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS fts_after_insert AFTER INSERT ON fragments BEGIN
                    INSERT INTO fragments_fts(rowid, content, windowTitle, appName, url)
                    VALUES (new.id, new.content, new.windowTitle, new.appName, new.url);
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS fts_after_delete AFTER DELETE ON fragments BEGIN
                    INSERT INTO fragments_fts(fragments_fts, rowid, content, windowTitle, appName, url)
                    VALUES ('delete', old.id, old.content, old.windowTitle, old.appName, old.url);
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS fts_after_update
                AFTER UPDATE OF content, windowTitle, appName, url ON fragments BEGIN
                    INSERT INTO fragments_fts(fragments_fts, rowid, content, windowTitle, appName, url)
                    VALUES ('delete', old.id, old.content, old.windowTitle, old.appName, old.url);
                    INSERT INTO fragments_fts(rowid, content, windowTitle, appName, url)
                    VALUES (new.id, new.content, new.windowTitle, new.appName, new.url);
                END
                """)
        }
    }

    // MARK: - Write

    // MARK: - Screenshot Storage

    private static let screenshotsDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("cobrain/screenshots", isDirectory: true)
    }()

    /// Save a CGImage as JPEG and return the relative path (day/timestamp.jpg).
    func saveScreenshot(_ image: CGImage, day: String, timestamp: Int) -> String? {
        let dayDir = Self.screenshotsDir.appendingPathComponent(day, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        } catch {
            log.error("Failed to create screenshots dir: \(error.localizedDescription)")
            return nil
        }

        let relativePath = "\(day)/\(timestamp).jpg"
        let fileURL = Self.screenshotsDir.appendingPathComponent(relativePath)

        guard let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            log.error("Failed to create image destination")
            return nil
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            log.error("Failed to write screenshot JPEG")
            return nil
        }

        return relativePath
    }

    /// Resolve a relative image path to an absolute URL.
    static func screenshotURL(for relativePath: String) -> URL {
        screenshotsDir.appendingPathComponent(relativePath)
    }

    /// Delete screenshot files older than the given number of days.
    func purgeScreenshots(olderThan days: Int) {
        let fm = FileManager.default
        let cutoffDay = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let cutoffStr = Fragment.makeDay(from: cutoffDay)

        guard let dayDirs = try? fm.contentsOfDirectory(at: Self.screenshotsDir, includingPropertiesForKeys: nil) else { return }
        for dir in dayDirs where dir.lastPathComponent < cutoffStr {
            try? fm.removeItem(at: dir)
            log.info("Purged screenshots for \(dir.lastPathComponent)")
        }
    }

    /// Delete oldest screenshot day-folders until total size is under the given limit.
    func purgeScreenshots(untilUnderMB limitMB: Int) {
        guard limitMB > 0 else { return }
        let limitBytes = Int64(limitMB) * 1024 * 1024
        var currentSize = screenshotsSizeBytes()
        guard currentSize > limitBytes else { return }

        let fm = FileManager.default
        guard let dayDirs = (try? fm.contentsOfDirectory(at: Self.screenshotsDir, includingPropertiesForKeys: nil))?
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) else { return }

        for dir in dayDirs {
            guard currentSize > limitBytes else { break }
            let dirSize = Self.directorySize(dir)
            try? fm.removeItem(at: dir)
            currentSize -= dirSize
            log.info("Purged screenshots for \(dir.lastPathComponent) to reclaim \(dirSize) bytes")
        }
    }

    /// Total size of all screenshots on disk in bytes.
    func screenshotsSizeBytes() -> Int64 {
        Self.directorySize(Self.screenshotsDir)
    }

    /// Total number of screenshot files on disk.
    func screenshotsCount() -> Int {
        let fm = FileManager.default
        guard let dayDirs = try? fm.contentsOfDirectory(at: Self.screenshotsDir, includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        for dir in dayDirs {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                count += files.count
            }
        }
        return count
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    @discardableResult
    func saveFragment(
        content: String,
        contentHash: String,
        focusedText: String?,
        bundleIdentifier: String,
        appName: String,
        windowTitle: String?,
        url: String?,
        appCategory: String?,
        summary: String? = nil,
        imagePath: String? = nil
    ) -> Int64? {
        let wordCount = content.split(separator: " ").count
        let now = Int(Date().timeIntervalSince1970)
        let day = Fragment.makeDay()

        var fragment = Fragment(
            id: nil,
            content: content,
            contentHash: contentHash,
            focusedText: focusedText,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            windowTitle: windowTitle,
            url: url,
            appCategory: appCategory,
            capturedAt: now,
            day: day,
            wordCount: wordCount,
            summary: summary,
            imagePath: imagePath
        )

        do {
            try dbPool.write { db in
                try fragment.insert(db)
            }
            log.debug("Saved fragment id=\(fragment.id ?? -1) words=\(wordCount)")
            return fragment.id
        } catch {
            log.error("Save error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Read

    func search(query: String, appFilter: String? = nil, limit: Int = 50) throws -> [FragmentSearchResult] {
        try dbPool.read { db in
            var sql = """
                SELECT f.*,
                       snippet(fragments_fts, 0, '<mark>', '</mark>', '...', 40) as snippet,
                       bm25(fragments_fts) as rank
                FROM fragments_fts
                JOIN fragments f ON f.id = fragments_fts.rowid
                WHERE fragments_fts MATCH ?
                """
            var args: [any DatabaseValueConvertible] = [query]

            if let app = appFilter {
                sql += " AND f.bundleIdentifier = ?"
                args.append(app)
            }

            sql += " ORDER BY rank LIMIT ?"
            args.append(limit)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return try rows.map { row in
                FragmentSearchResult(
                    fragment: try Fragment(row: row),
                    snippet: row["snippet"] as? String ?? "",
                    rank: row["rank"] as? Double ?? 0.0
                )
            }
        }
    }

    func recentFragments(limit: Int = 20) throws -> [Fragment] {
        try dbPool.read { db in
            try Fragment
                .order(Fragment.Columns.capturedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func appSummaries() throws -> [AppSummary] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT appName, bundleIdentifier, COUNT(*) as count,
                       MAX(capturedAt) as lastCaptured
                FROM fragments
                GROUP BY bundleIdentifier
                ORDER BY count DESC
                """)
            return rows.map { row in
                AppSummary(
                    appName: row["appName"],
                    bundleIdentifier: row["bundleIdentifier"],
                    count: row["count"],
                    lastCaptured: row["lastCaptured"]
                )
            }
        }
    }

    func fragments(forApp bundleID: String, limit: Int = 100) throws -> [Fragment] {
        try dbPool.read { db in
            try Fragment
                .filter(Fragment.Columns.bundleIdentifier == bundleID)
                .order(Fragment.Columns.capturedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fragmentsForDay(_ day: String) throws -> [Fragment] {
        try dbPool.read { db in
            try Fragment
                .filter(Fragment.Columns.day == day)
                .order(Fragment.Columns.capturedAt.asc)
                .fetchAll(db)
        }
    }

    func todayFragmentCount() throws -> Int {
        try dbPool.read { db in
            let today = Fragment.makeDay()
            return try Fragment
                .filter(Fragment.Columns.day == today)
                .fetchCount(db)
        }
    }

    func totalFragmentCount() throws -> Int {
        try dbPool.read { db in
            try Fragment.fetchCount(db)
        }
    }

    func databaseSize() -> Int64 {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbPath = appSupport.appendingPathComponent("cobrain/brain.sqlite")
        let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    func fragmentsByAppName(_ name: String, limit: Int = 10) throws -> [Fragment] {
        try dbPool.read { db in
            try Fragment.fetchAll(db, sql: """
                SELECT * FROM fragments
                WHERE appName LIKE ? COLLATE NOCASE
                ORDER BY capturedAt DESC LIMIT ?
                """, arguments: ["%\(name)%", limit])
        }
    }

    // MARK: - Pending Captures

    @discardableResult
    func savePendingCapture(
        imagePath: String,
        bundleIdentifier: String,
        appName: String,
        windowTitle: String?,
        url: String?,
        appCategory: String?
    ) -> Int64? {
        var pending = PendingCapture(
            id: nil,
            imagePath: imagePath,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            windowTitle: windowTitle,
            url: url,
            appCategory: appCategory,
            capturedAt: Int(Date().timeIntervalSince1970),
            day: Fragment.makeDay()
        )

        do {
            try dbPool.write { db in
                try pending.insert(db)
            }
            return pending.id
        } catch {
            log.error("Save pending capture error: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchPendingCaptures(limit: Int = 50) throws -> [PendingCapture] {
        try dbPool.read { db in
            try PendingCapture
                .order(PendingCapture.Columns.capturedAt.asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func deletePendingCapture(id: Int64) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM pending_captures WHERE id = ?", arguments: [id])
        }
    }

    func pendingCaptureCount() throws -> Int {
        try dbPool.read { db in
            try PendingCapture.fetchCount(db)
        }
    }

    // MARK: - Summary

    func unsummarizedFragments(limit: Int = 5) throws -> [Fragment] {
        try dbPool.read { db in
            try Fragment
                .filter(Fragment.Columns.summary == nil)
                .filter(Fragment.Columns.wordCount > 5)
                .order(Fragment.Columns.capturedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func updateFragmentSummary(id: Int64, summary: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE fragments SET summary = ? WHERE id = ?",
                arguments: [summary, id]
            )
        }
    }

    // MARK: - Purge

    @discardableResult
    func purgeOlderThan(days: Int) throws -> Int {
        let count = try dbPool.write { db in
            let cutoff = Int(Date().timeIntervalSince1970) - (days * 86400)
            try db.execute(sql: "DELETE FROM fragments WHERE capturedAt < ?", arguments: [cutoff])
            return db.changesCount
        }
        purgeScreenshots(olderThan: days)
        return count
    }

    /// Purge text fragments older than the given number of days.
    @discardableResult
    func purgeText(olderThan days: Int) throws -> Int {
        try dbPool.write { db in
            let cutoff = Int(Date().timeIntervalSince1970) - (days * 86400)
            try db.execute(sql: "DELETE FROM fragments WHERE capturedAt < ?", arguments: [cutoff])
            return db.changesCount
        }
    }

    /// Run the full storage policy: time-based + size-based cleanup.
    func applyStoragePolicy(screenshotDays: Int, textDays: Int, maxScreenshotMB: Int) {
        // 1. Delete screenshots older than screenshotDays
        purgeScreenshots(olderThan: screenshotDays)
        // 2. If still over size limit, delete oldest days until under
        purgeScreenshots(untilUnderMB: maxScreenshotMB)
        // 3. Delete text fragments older than textDays
        try? purgeText(olderThan: textDays)
    }

    /// Delete all screenshots from disk (keeps text fragments).
    func deleteAllScreenshots() {
        let fm = FileManager.default
        guard let dayDirs = try? fm.contentsOfDirectory(at: Self.screenshotsDir, includingPropertiesForKeys: nil) else { return }
        for dir in dayDirs {
            try? fm.removeItem(at: dir)
        }
        // Clear imagePath references in DB
        try? dbPool.write { db in
            try db.execute(sql: "UPDATE fragments SET imagePath = NULL")
        }
        log.info("Deleted all screenshots")
    }

    /// Delete all text fragments from DB (keeps screenshot files).
    func deleteAllText() throws -> Int {
        let count = try dbPool.write { db in
            try db.execute(sql: "DELETE FROM fragments")
            return db.changesCount
        }
        log.info("Deleted all text fragments (\(count) rows)")
        return count
    }

    func checkpoint() {
        try? dbPool.write { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }
}
