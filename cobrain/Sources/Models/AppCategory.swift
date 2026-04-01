import AppKit

enum AppCategory: String, Codable, CaseIterable {
    case code
    case browsing
    case communication
    case email
    case work
    case design
    case other

    // Bundle ID prefix → category (adapted from Vox's FrontmostAppService)
    private static let prefixMappings: [(prefix: String, category: AppCategory)] = [
        // Code — IDEs & editors
        ("com.apple.dt.Xcode", .code),
        ("com.microsoft.VSCode", .code),
        ("com.todesktop.230313mzl4w4u92", .code),  // Cursor
        ("com.jetbrains.", .code),
        ("com.sublimetext.", .code),
        ("com.panic.Nova", .code),
        // Code — terminals
        ("com.apple.Terminal", .code),
        ("com.googlecode.iterm2", .code),
        ("dev.warp.Warp", .code),
        ("net.kovidgoyal.kitty", .code),
        ("io.alacritty", .code),
        // Browsing
        ("com.apple.Safari", .browsing),
        ("com.google.Chrome", .browsing),
        ("company.thebrowser.Browser", .browsing), // Arc
        ("org.mozilla.firefox", .browsing),
        ("com.brave.Browser", .browsing),
        // Communication
        ("com.tinyspeck.slackmacgap", .communication),
        ("com.microsoft.teams", .communication),
        ("com.hnc.Discord", .communication),
        ("ru.keepcoder.Telegram", .communication),
        // Email
        ("com.apple.mail", .email),
        ("com.microsoft.Outlook", .email),
        ("com.readdle.smartemail", .email),
        // Work
        ("com.linear", .work),
        ("com.atlassian.jira", .work),
        ("com.notion.id", .work),
        // Design
        ("com.figma.Desktop", .design),
        ("com.bohemiancoding.sketch3", .design),
    ]

    static func from(bundleID: String) -> AppCategory {
        for (prefix, category) in prefixMappings where bundleID.hasPrefix(prefix) {
            return category
        }
        return .other
    }
}
