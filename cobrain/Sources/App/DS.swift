import SwiftUI

// MARK: - Design System

enum DS {

    // MARK: - Colors (Amber/Gold palette)

    enum Colors {
        static let bg = adaptive(
            light: (0.97, 0.96, 0.95),
            dark: (0.08, 0.07, 0.07)
        )
        static let surface = adaptive(
            light: (1.0, 0.99, 0.98),
            dark: (0.13, 0.12, 0.11)
        )
        static let surfaceHover = adaptive(
            light: (0.94, 0.93, 0.91),
            dark: (0.17, 0.16, 0.15)
        )
        static let border = adaptive(
            light: (0.88, 0.86, 0.84),
            dark: (0.22, 0.20, 0.18)
        )
        static let text = adaptive(
            light: (0.12, 0.11, 0.10),
            dark: (0.93, 0.91, 0.88)
        )
        static let textSecondary = adaptive(
            light: (0.48, 0.45, 0.42),
            dark: (0.55, 0.52, 0.48)
        )
        // Amber/gold accent
        static let accent = adaptive(
            light: (0.80, 0.58, 0.10),
            dark: (0.92, 0.70, 0.20)
        )
        static let success = adaptive(
            light: (0.20, 0.60, 0.35),
            dark: (0.30, 0.72, 0.45)
        )
        static let error = Color.red

        // NSColor versions for AttributedString
        static let textNS = adaptiveNS(
            light: (0.12, 0.11, 0.10),
            dark: (0.93, 0.91, 0.88)
        )
        static let textSecondaryNS = adaptiveNS(
            light: (0.48, 0.45, 0.42),
            dark: (0.55, 0.52, 0.48)
        )

        private static func adaptive(
            light: (CGFloat, CGFloat, CGFloat),
            dark: (CGFloat, CGFloat, CGFloat)
        ) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let c = isDark ? dark : light
                return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
            })
        }

        private static func adaptiveNS(
            light: (CGFloat, CGFloat, CGFloat),
            dark: (CGFloat, CGFloat, CGFloat)
        ) -> NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let c = isDark ? dark : light
                return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
            }
        }
    }

    // MARK: - Typography

    enum Fonts {
        static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let subtitle = Font.system(size: 14, weight: .medium)
        static let body = Font.system(size: 13)
        static let bodySmall = Font.system(size: 12)
        static let caption = Font.system(size: 11, weight: .medium)
        static let captionSmall = Font.system(size: 10, weight: .medium, design: .rounded)
        static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
        static let search = Font.system(size: 16)
        static let searchResult = Font.system(size: 13)
        static let sectionHeader = Font.system(size: 11, weight: .semibold, design: .rounded)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 5
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let panel: CGFloat = 16
    }
}

// MARK: - View Modifiers

struct DSCardModifier: ViewModifier {
    var filled: Bool = true
    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(filled ? DS.Colors.surface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
    }
}

struct DSFragmentCardModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isHovered ? DS.Colors.surfaceHover : DS.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct DSKeyBadgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.Fonts.captionSmall)
            .foregroundStyle(DS.Colors.textSecondary)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).stroke(DS.Colors.border, lineWidth: 0.5))
    }
}

extension View {
    func dsCard(filled: Bool = true) -> some View {
        modifier(DSCardModifier(filled: filled))
    }

    func dsFragmentCard() -> some View {
        modifier(DSFragmentCardModifier())
    }

    func dsKeyBadge() -> some View {
        modifier(DSKeyBadgeModifier())
    }
}
