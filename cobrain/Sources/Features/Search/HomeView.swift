import SwiftUI
import Sparkle
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "home")

enum AppScreen: Equatable {
    case home
    case timeline
    case replay
    case chat
    case browse
    case settings
    case results(String)
}

struct HomeView: View {
    let settings: AppSettings
    let updater: SPUUpdater

    @State private var screen: AppScreen = .home
    @State private var query: String = ""
    @State private var appSummaries: [AppSummary] = []
    @State private var todayCount: Int = 0
    @State private var totalCount: Int = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Main content
            Group {
                switch screen {
                case .home:
                    homeScreen
                case .results(let q):
                    SearchResultsView(query: q) {
                        screen = .home
                    }
                case .timeline:
                    TimelineView()
                case .replay:
                    ReplayView()
                case .chat:
                    ChatView()
                case .browse:
                    BrowserView()
                case .settings:
                    SettingsView(settings: settings, updater: updater)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom status bar
            bottomBar
        }
        .background(DS.Colors.bg)
        .onAppear { loadStats() }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            screen = .home
            searchFocused = true
        }
    }

    // MARK: - Home Screen (Spool-like)

    private var homeScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            // Title
            VStack(spacing: DS.Spacing.sm) {
                HStack(spacing: 0) {
                    Text("Cobrain")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(DS.Colors.text)
                    Text(".")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(DS.Colors.accent)
                }

                Text("A local search engine for your memory.")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .padding(.bottom, DS.Spacing.xxl)

            // Search bar
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DS.Colors.textSecondary)
                    .font(.system(size: 15))

                TextField("Search my memory...", text: $query)
                    .font(.system(size: 15))
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !q.isEmpty else { return }
                        screen = .results(q)
                    }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(DS.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
            .frame(maxWidth: 480)
            .padding(.bottom, DS.Spacing.lg)

            // Source chips
            if !appSummaries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(appSummaries.prefix(6)) { app in
                            sourceChip(app: app)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                }
                .frame(maxWidth: 560)
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.xxl)
    }

    // MARK: - Source Chip

    private func sourceChip(app: AppSummary) -> some View {
        Button {
            query = "app:\(app.appName.lowercased())"
            screen = .results(query)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Circle()
                    .fill(colorForApp(app.bundleIdentifier))
                    .frame(width: 6, height: 6)

                Text(app.appName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Colors.text)

                Text("\(app.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(DS.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            // Capture status
            Circle()
                .fill(settings.captureEnabled ? Color.green : Color.gray)
                .frame(width: 6, height: 6)

            Text("Capturing")
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.textSecondary)

            Text("·")
                .foregroundStyle(DS.Colors.textSecondary)

            Text("\(totalCount) fragments")
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.textSecondary)

            // Model status
            modelStatusBar

            Spacer()

            // Nav buttons
            bottomButton(icon: "house", label: "Home", active: screen == .home) {
                screen = .home
            }

            bottomButton(icon: "clock", label: "Timeline", active: screen == .timeline) {
                screen = .timeline
            }

            bottomButton(icon: "play.rectangle", label: "Replay", active: screen == .replay) {
                screen = .replay
            }

            bottomButton(icon: "bubble.left.and.text.bubble.right", label: "Chat", active: screen == .chat) {
                screen = .chat
            }

            bottomButton(icon: "square.grid.2x2", label: "Browse", active: screen == .browse) {
                screen = .browse
            }

            bottomButton(icon: "gearshape", label: "Settings", active: screen == .settings) {
                screen = .settings
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Colors.bg)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Model Status (Bottom Bar)

    @ViewBuilder
    private var modelStatusBar: some View {
        let status = ModelManager.shared.status
        switch status {
        case .idle:
            EmptyView()
        case .downloading(let progress):
            HStack(spacing: DS.Spacing.xs) {
                Text("·")
                    .foregroundStyle(DS.Colors.textSecondary)
                ProgressView(value: progress)
                    .frame(width: 40)
                    .tint(DS.Colors.accent)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
        case .loading:
            HStack(spacing: DS.Spacing.xs) {
                Text("·")
                    .foregroundStyle(DS.Colors.textSecondary)
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Text("Loading model…")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
        case .ready:
            HStack(spacing: DS.Spacing.xs) {
                Text("·")
                    .foregroundStyle(DS.Colors.textSecondary)
                Image(systemName: "brain")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        case .inferring:
            HStack(spacing: DS.Spacing.xs) {
                Text("·")
                    .foregroundStyle(DS.Colors.textSecondary)
                Image(systemName: "brain")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Colors.accent)
                    .symbolEffect(.pulse)
                Text("Thinking…")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
        case .error:
            HStack(spacing: DS.Spacing.xs) {
                Text("·")
                    .foregroundStyle(DS.Colors.textSecondary)
                Button {
                    Task { await ModelManager.shared.reloadModel() }
                } label: {
                    HStack(spacing: DS.Spacing.xxs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Colors.error)
                        Text("Model error")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Colors.error)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bottomButton(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(active ? DS.Colors.accent : DS.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func loadStats() {
        appSummaries = (try? StorageManager.shared.appSummaries()) ?? []
        todayCount = (try? StorageManager.shared.todayFragmentCount()) ?? 0
        totalCount = (try? StorageManager.shared.totalFragmentCount()) ?? 0
    }

    private func colorForApp(_ bundleID: String) -> Color {
        let cat = AppCategory.from(bundleID: bundleID)
        switch cat {
        case .code: return .blue
        case .browsing: return .orange
        case .communication: return .green
        case .email: return .purple
        case .work: return .indigo
        case .design: return .pink
        case .other: return .gray
        }
    }
}
