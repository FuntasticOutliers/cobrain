import ApplicationServices
import AppKit
import Foundation
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "windowmeta")

struct WindowMetadata: Sendable {
    let windowTitle: String?
    let browserURL: String?
}

final class WindowMetadataService {
    static let shared = WindowMetadataService()

    /// Browser bundle IDs that may expose a URL
    private let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "company.thebrowser.Browser",  // Arc
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.microsoft.edgemac",
    ]

    // MARK: - Public

    /// Read window title and (for browsers) the URL.
    /// These are cheap single-attribute AX reads, no tree traversal.
    func metadata(for pid: pid_t, bundleID: String) -> WindowMetadata {
        let appElement = AXUIElementCreateApplication(pid)
        let isBrowser = browserBundleIDs.contains(bundleID)

        let windowTitle = getWindowTitle(appElement)

        var browserURL: String?
        if isBrowser {
            browserURL = getDocumentURL(appElement)
                ?? extractBrowserURL(appElement)
                ?? getChromeTitleViaAppleScript(bundleID: bundleID).flatMap { extractURLFromAppleScript($0) }
        }

        return WindowMetadata(windowTitle: windowTitle, browserURL: browserURL)
    }

    // MARK: - Accessibility Permission

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Attribute Reading

    private func readAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    private func readStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        readAttribute(element, attribute) as? String
    }

    private func hasAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var names: CFArray?
        AXUIElementCopyAttributeNames(element, &names)
        guard let attrs = names as? [String] else { return false }
        return attrs.contains(attribute)
    }

    // MARK: - Window Title

    private func getWindowTitle(_ app: AXUIElement) -> String? {
        guard let windowRef = readAttribute(app, kAXFocusedWindowAttribute as String) else { return nil }
        return readStringAttribute(windowRef as! AXUIElement, kAXTitleAttribute as String)
    }

    // MARK: - Document URL (browsers expose this on the window)

    private func getDocumentURL(_ app: AXUIElement) -> String? {
        guard let windowRef = readAttribute(app, kAXFocusedWindowAttribute as String) else { return nil }
        return readStringAttribute(windowRef as! AXUIElement, "AXDocument")
    }

    // MARK: - Browser URL from Address Bar

    private func extractBrowserURL(_ app: AXUIElement) -> String? {
        guard let windowRef = readAttribute(app, kAXFocusedWindowAttribute as String) else {
            return nil
        }
        return findAddressBar(windowRef as! AXUIElement, depth: 0)
    }

    private func findAddressBar(_ element: AXUIElement, depth: Int) -> String? {
        guard depth < 6 else { return nil }

        if let role = readStringAttribute(element, kAXRoleAttribute as String),
           role == "AXTextField" || role == "AXComboBox" {
            if let desc = readStringAttribute(element, kAXDescriptionAttribute as String),
               desc.localizedCaseInsensitiveContains("address") ||
               desc.localizedCaseInsensitiveContains("url") ||
               desc.localizedCaseInsensitiveContains("location") {
                return readStringAttribute(element, kAXValueAttribute as String)
            }
            if let value = readStringAttribute(element, kAXValueAttribute as String),
               (value.hasPrefix("http") || value.contains(".com") || value.contains(".org") || value.contains("localhost")),
               !hasAttribute(element, "AXDOMClassList") {
                return value
            }
        }

        guard let childrenRef = readAttribute(element, kAXChildrenAttribute as String),
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if let url = findAddressBar(child, depth: depth + 1) {
                return url
            }
        }
        return nil
    }

    // MARK: - AppleScript Fallback

    private func getChromeTitleViaAppleScript(bundleID: String?) -> String? {
        guard let bundleID else { return nil }

        let appName: String
        switch bundleID {
        case "com.google.Chrome": appName = "Google Chrome"
        case "com.apple.Safari": appName = "Safari"
        case "company.thebrowser.Browser": appName = "Arc"
        case "com.brave.Browser": appName = "Brave Browser"
        default: return nil
        }

        let script: String
        if bundleID == "com.apple.Safari" {
            script = """
            tell application "\(appName)"
                set pageTitle to name of current tab of front window
                set pageURL to URL of current tab of front window
                return pageTitle & " — " & pageURL
            end tell
            """
        } else {
            script = """
            tell application "\(appName)"
                set pageTitle to title of active tab of front window
                set pageURL to URL of active tab of front window
                return pageTitle & " — " & pageURL
            end tell
            """
        }

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        if let result = appleScript?.executeAndReturnError(&error) {
            return result.stringValue
        }
        return nil
    }

    /// Extract URL from AppleScript result which returns "Title — URL"
    private func extractURLFromAppleScript(_ result: String) -> String? {
        let parts = result.components(separatedBy: " — ")
        guard parts.count >= 2 else { return nil }
        let url = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines)
        return url?.isEmpty == false ? url : nil
    }
}
