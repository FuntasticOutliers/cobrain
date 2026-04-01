import SwiftUI
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "search")

// MARK: - Search Results View (navigated to from Home)

struct SearchResultsView: View {
    let query: String
    let onBack: () -> Void

    @State private var results: [FragmentSearchResult] = []
    @State private var expandedId: Int64?

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with back + search
            HStack(spacing: DS.Spacing.sm) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .buttonStyle(.plain)

                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(DS.Colors.textSecondary)
                        .font(.system(size: 13))

                    Text(query)
                        .font(DS.Fonts.body)
                        .foregroundStyle(DS.Colors.text)

                    Spacer()

                    Text("\(results.count) results")
                        .font(DS.Fonts.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .fill(DS.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(DS.Colors.border, lineWidth: 0.5)
                )
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)

            Divider()

            // Results
            if results.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    Spacer()
                    Text("No fragments match \"\(query)\"")
                        .font(DS.Fonts.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                    Text("Try a different search term.")
                        .font(DS.Fonts.bodySmall)
                        .foregroundStyle(DS.Colors.textSecondary.opacity(0.7))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Spacing.sm) {
                        ForEach(results, id: \.fragment.id) { result in
                            FragmentRowView(
                                fragment: result.fragment,
                                snippet: result.snippet,
                                expanded: expandedId == result.fragment.id
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    expandedId = expandedId == result.fragment.id ? nil : result.fragment.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }
            }
        }
        .onAppear { performSearch() }
    }

    private func performSearch() {
        do {
            let sanitized = query
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            results = try StorageManager.shared.search(query: "\(sanitized)*")
            log.info("Search '\(query)' returned \(results.count) results")
        } catch {
            log.error("Search error: \(error.localizedDescription)")
            results = []
        }
    }
}

// MARK: - Fragment Row

struct FragmentRowView: View {
    let fragment: Fragment
    let snippet: String?
    let expanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                // Header
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: fragment.appIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.accent)

                    Text(fragment.appName)
                        .font(DS.Fonts.caption)
                        .foregroundStyle(DS.Colors.text)

                    if let title = fragment.windowTitle, !title.isEmpty {
                        Text("·")
                            .foregroundStyle(DS.Colors.textSecondary)
                        Text(title)
                            .font(DS.Fonts.caption)
                            .foregroundStyle(DS.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(fragment.relativeTime)
                        .font(DS.Fonts.captionSmall)
                        .foregroundStyle(DS.Colors.textSecondary)
                }

                // Content
                if expanded {
                    Text(fragment.content)
                        .font(fragment.appCategory == "code" ? DS.Fonts.mono : DS.Fonts.searchResult)
                        .foregroundStyle(DS.Colors.text)
                        .textSelection(.enabled)

                    if let url = fragment.url, !url.isEmpty {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                            Text(url)
                                .font(DS.Fonts.captionSmall)
                                .lineLimit(1)
                        }
                        .foregroundStyle(DS.Colors.accent)
                    }

                    HStack(spacing: DS.Spacing.md) {
                        Button("Copy Text") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(fragment.content, forType: .string)
                        }
                        .font(DS.Fonts.caption)

                        if let url = fragment.url, let nsURL = URL(string: url) {
                            Button("Open URL") {
                                NSWorkspace.shared.open(nsURL)
                            }
                            .font(DS.Fonts.caption)
                        }
                    }
                    .foregroundStyle(DS.Colors.accent)
                    .padding(.top, DS.Spacing.xs)
                } else {
                    if let snippet, !snippet.isEmpty {
                        Text(cleanSnippet(snippet))
                            .font(DS.Fonts.searchResult)
                            .foregroundStyle(DS.Colors.text)
                            .lineLimit(3)
                    } else {
                        Text(fragment.content)
                            .font(DS.Fonts.searchResult)
                            .foregroundStyle(DS.Colors.text)
                            .lineLimit(3)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .dsFragmentCard()
    }

    private func cleanSnippet(_ snippet: String) -> String {
        snippet.replacingOccurrences(of: "<mark>", with: "")
            .replacingOccurrences(of: "</mark>", with: "")
    }
}
