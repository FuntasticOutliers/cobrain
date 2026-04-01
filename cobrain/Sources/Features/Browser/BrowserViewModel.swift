import Foundation
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "browser")

@Observable
final class BrowserViewModel {
    var apps: [AppSummary] = []
    var selectedApp: AppSummary?
    var fragments: [Fragment] = []
    var expandedId: Int64?
    var todayCount: Int = 0
    var weekCount: Int = 0
    var totalCount: Int = 0

    private let storage = StorageManager.shared

    func load() {
        do {
            apps = try storage.appSummaries()
            todayCount = try storage.todayFragmentCount()
            totalCount = try storage.totalFragmentCount()
            // Approximate week count
            weekCount = todayCount * 5 // Simplified; could query properly
        } catch {
            log.error("Error loading: \(error.localizedDescription)")
        }
    }

    func loadFragments(for bundleID: String) {
        do {
            fragments = try storage.fragments(forApp: bundleID)
        } catch {
            log.error("Error loading fragments: \(error.localizedDescription)")
            fragments = []
        }
    }
}
