import Foundation
import SwiftUI

enum AppTheme: String, CaseIterable {
    case light, dark, system

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

enum SupportedModel: String, CaseIterable, Identifiable {
    // Qwen 3 VL
    case qwen3VL2B = "mlx-community/Qwen3-VL-2B-Instruct-4bit"
    case qwen3VL4B = "mlx-community/Qwen3-VL-4B-Instruct-4bit"
    // Qwen 2.5 VL
    case qwen25VL3B = "mlx-community/Qwen2.5-VL-3B-Instruct-4bit"
    case qwen25VL7B = "mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
    // Gemma 3
    case gemma3_4B = "mlx-community/gemma-3-4b-it-4bit"
    // SmolVLM
    case smolVLM = "mlx-community/SmolVLM-Instruct-4bit"
    case smolVLM2 = "mlx-community/SmolVLM2-2.2B-Instruct-mlx"

    var id: String { rawValue }

    var category: String {
        switch self {
        case .qwen3VL2B, .qwen3VL4B: "Qwen 3 VL"
        case .qwen25VL3B, .qwen25VL7B: "Qwen 2.5 VL"
        case .gemma3_4B: "Gemma 3"
        case .smolVLM, .smolVLM2: "SmolVLM"
        }
    }

    var displayName: String {
        switch self {
        case .qwen3VL2B: "Qwen 3 VL 2B"
        case .qwen3VL4B: "Qwen 3 VL 4B (recommended)"
        case .qwen25VL3B: "Qwen 2.5 VL 3B"
        case .qwen25VL7B: "Qwen 2.5 VL 7B"
        case .gemma3_4B: "Gemma 3 4B"
        case .smolVLM: "SmolVLM 465M"
        case .smolVLM2: "SmolVLM2 2.2B"
        }
    }

    var sizeHint: String {
        switch self {
        case .qwen3VL2B: "~1.5 GB"
        case .qwen3VL4B: "~2.5 GB"
        case .qwen25VL3B: "~1.8 GB"
        case .qwen25VL7B: "~4.6 GB"
        case .gemma3_4B: "~2.5 GB"
        case .smolVLM: "~0.5 GB"
        case .smolVLM2: "~2.2 GB"
        }
    }

    static var grouped: [(category: String, models: [SupportedModel])] {
        let order = ["Qwen 3 VL", "Qwen 2.5 VL", "Gemma 3", "SmolVLM"]
        let dict = Dictionary(grouping: allCases, by: \.category)
        return order.compactMap { key in
            dict[key].map { (category: key, models: $0) }
        }
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var captureEnabled: Bool {
        didSet { UserDefaults.standard.set(captureEnabled, forKey: "captureEnabled") }
    }

    var excludedBundleIDs: [String] {
        didSet { UserDefaults.standard.set(excludedBundleIDs, forKey: "excludedBundleIDs") }
    }

    var captureIntervalSeconds: Int {
        didSet { UserDefaults.standard.set(captureIntervalSeconds, forKey: "captureIntervalSeconds") }
    }

    var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: "retentionDays") }
    }

    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }

    var modelID: String {
        didSet { UserDefaults.standard.set(modelID, forKey: "modelID") }
    }

    /// Fraction of pixels that must differ to trigger VLM inference (0.0–1.0).
    /// Lower = more sensitive (more VLM calls). Default 0.05 = 5% of pixels.
    var changeDetectionThreshold: Double {
        didSet { UserDefaults.standard.set(changeDetectionThreshold, forKey: "changeDetectionThreshold") }
    }

    /// Maximum capture interval (seconds) when no change is detected.
    /// The scheduler backs off from captureIntervalSeconds up to this value.
    var maxCaptureIntervalSeconds: Int {
        didSet { UserDefaults.standard.set(maxCaptureIntervalSeconds, forKey: "maxCaptureIntervalSeconds") }
    }

    private init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.captureEnabled = UserDefaults.standard.object(forKey: "captureEnabled") as? Bool ?? true
        self.excludedBundleIDs = UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [
            "com.1password.1password",
            "com.agilebits.onepassword7",
            "com.apple.keychainaccess",
        ]
        let interval = UserDefaults.standard.integer(forKey: "captureIntervalSeconds")
        self.captureIntervalSeconds = interval > 0 ? interval : 5
        let retention = UserDefaults.standard.integer(forKey: "retentionDays")
        self.retentionDays = retention > 0 ? retention : 90
        self.theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .light
        self.modelID = UserDefaults.standard.string(forKey: "modelID")
            ?? SupportedModel.qwen3VL4B.rawValue
        let threshold = UserDefaults.standard.double(forKey: "changeDetectionThreshold")
        self.changeDetectionThreshold = threshold > 0 ? threshold : 0.05
        let maxInterval = UserDefaults.standard.integer(forKey: "maxCaptureIntervalSeconds")
        self.maxCaptureIntervalSeconds = maxInterval > 0 ? maxInterval : 30
    }

    func isExcluded(_ bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    func exclude(_ bundleID: String) {
        guard !excludedBundleIDs.contains(bundleID) else { return }
        excludedBundleIDs.append(bundleID)
    }

    func unexclude(_ bundleID: String) {
        excludedBundleIDs.removeAll { $0 == bundleID }
    }
}
