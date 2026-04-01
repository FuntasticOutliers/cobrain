import AppKit

struct AppContext: Sendable {
    let bundleIdentifier: String
    let appName: String
    let pid: pid_t
    let category: AppCategory
}

final class ContextDetectionService {
    static let shared = ContextDetectionService()

    private static let selfBundleID = "dev.cobrain.app"

    func frontmostContext() -> AppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Self.selfBundleID else { return nil }

        return AppContext(
            bundleIdentifier: bundleID,
            appName: app.localizedName ?? "Unknown",
            pid: app.processIdentifier,
            category: AppCategory.from(bundleID: bundleID)
        )
    }
}
