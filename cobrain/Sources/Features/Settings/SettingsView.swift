import SwiftUI
import Sparkle

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case model = "Model"
    case privacy = "Privacy"
    case storage = "Storage"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .model: "cpu"
        case .privacy: "eye.slash"
        case .storage: "externaldrive"
        }
    }
}

struct SettingsView: View {
    let settings: AppSettings
    let updater: SPUUpdater

    @State private var selectedSection: SettingsSection = .general
    @State private var dbSize: String = "..."
    @State private var screenshotsSize: String = "..."
    @State private var screenshotsCount: Int = 0
    @State private var totalFragments: Int = 0
    @State private var showDeleteConfirmation = false
    @State private var showingAppPicker = false
    @State private var appSearchText = ""

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: section.icon)
                                .font(.system(size: 12))
                                .frame(width: 16)
                            Text(section.rawValue)
                                .font(DS.Fonts.body)
                        }
                        .foregroundStyle(selectedSection == section ? DS.Colors.accent : DS.Colors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(selectedSection == section ? DS.Colors.accent.opacity(0.1) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(DS.Spacing.md)
            .frame(width: 160)
            .background(DS.Colors.bg)

            Divider()

            // Detail
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    Text(selectedSection.rawValue)
                        .font(DS.Fonts.title)
                        .foregroundStyle(DS.Colors.text)

                    detailContent
                }
                .padding(DS.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { loadStats() }
        .alert("Delete Everything?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                try? StorageManager.shared.purgeOlderThan(days: 0)
                loadStats()
            }
        } message: {
            Text("This will permanently delete all screenshots and text data. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .general: generalSection
        case .model: modelSection
        case .privacy: privacySection
        case .storage: storageSection
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Toggle("Enable capture", isOn: Binding(
                    get: { settings.captureEnabled },
                    set: { settings.captureEnabled = $0 }
                ))
                .font(DS.Fonts.body)
                .foregroundStyle(DS.Colors.text)

                HStack {
                    Text("Capture frequency")
                        .font(DS.Fonts.body)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    Text("\(settings.captureIntervalSeconds)s")
                        .font(DS.Fonts.mono)
                        .foregroundStyle(DS.Colors.textSecondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(settings.captureIntervalSeconds) },
                        set: { settings.captureIntervalSeconds = Int($0) }
                    ),
                    in: 2...30,
                    step: 1
                )
                .tint(DS.Colors.accent)

                Divider()

                Picker("Theme", selection: Binding(
                    get: { settings.theme },
                    set: { settings.theme = $0 }
                )) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue.capitalized).tag(theme)
                    }
                }
                .font(DS.Fonts.body)
                .foregroundStyle(DS.Colors.text)

                Divider()

                Text("Cobrain v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")")
                    .font(DS.Fonts.bodySmall)
                    .foregroundStyle(DS.Colors.textSecondary)

                HStack(spacing: DS.Spacing.md) {
                    Button("Check for Updates...") {
                        updater.checkForUpdates()
                    }
                    .font(DS.Fonts.body)
                }

                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                .font(DS.Fonts.body)
                .foregroundStyle(DS.Colors.text)
            }
            .dsCard()
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Vision model used to understand screenshots.")
                .font(DS.Fonts.bodySmall)
                .foregroundStyle(DS.Colors.textSecondary)

            HStack {
                Text("Model")
                    .font(DS.Fonts.body)
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.modelID },
                    set: {
                        settings.modelID = $0
                        Task { await ModelManager.shared.reloadModel() }
                    }
                )) {
                    ForEach(SupportedModel.grouped, id: \.category) { group in
                        Section(group.category) {
                            ForEach(group.models) { model in
                                Text("\(model.displayName)  (\(model.sizeHint))")
                                    .tag(model.rawValue)
                            }
                        }
                    }
                }
                .frame(maxWidth: 320)
            }

            HStack {
                Text("Status")
                    .font(DS.Fonts.body)
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                modelStatusView
            }

            HStack {
                Text("Queue")
                    .font(DS.Fonts.body)
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                Text("\(ModelManager.shared.pendingCount) pending")
                    .font(DS.Fonts.mono)
                    .foregroundStyle(DS.Colors.textSecondary)
            }

            HStack(spacing: DS.Spacing.md) {
                if ModelManager.shared.pendingCount > 0,
                   ModelManager.shared.status == .idle || ModelManager.shared.status == .ready {
                    Button("Process Queue") {
                        Task { await BatchInferenceCoordinator.shared.flushNow() }
                    }
                    .font(DS.Fonts.body)
                }

                if ModelManager.shared.isReady || ModelManager.shared.status == .loading {
                    Button("Stop Model") {
                        ModelManager.shared.unloadModel()
                    }
                    .font(DS.Fonts.body)
                    .foregroundStyle(DS.Colors.error)
                }
            }
        }
        .dsCard()
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("These apps will never be captured.")
                .font(DS.Fonts.bodySmall)
                .foregroundStyle(DS.Colors.textSecondary)

            ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                HStack {
                    Text(displayName(for: bundleID))
                        .font(DS.Fonts.body)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    Button {
                        settings.unexclude(bundleID)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, DS.Spacing.xs)
            }

            Button {
                appSearchText = ""
                showingAppPicker = true
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("Add App…")
                        .font(DS.Fonts.body)
                }
                .foregroundStyle(DS.Colors.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, DS.Spacing.xs)
            .sheet(isPresented: $showingAppPicker) {
                AppPickerSheet(settings: settings, searchText: $appSearchText, availableApps: availableApps)
            }
        }
        .dsCard()
    }

    // MARK: - Storage

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Screenshots")
                .font(DS.Fonts.body.bold())
                .foregroundStyle(DS.Colors.text)

            Picker("Keep for", selection: Binding(
                get: { settings.screenshotRetentionDays },
                set: { settings.screenshotRetentionDays = $0 }
            )) {
                Text("30 days").tag(30)
                Text("60 days").tag(60)
                Text("90 days").tag(90)
                Text("180 days").tag(180)
                Text("365 days").tag(365)
            }
            .font(DS.Fonts.body)
            .foregroundStyle(DS.Colors.text)

            Picker("Max disk", selection: Binding(
                get: { settings.maxScreenshotSizeMB },
                set: { settings.maxScreenshotSizeMB = $0 }
            )) {
                Text("1 GB").tag(1024)
                Text("2 GB").tag(2048)
                Text("5 GB").tag(5120)
                Text("10 GB").tag(10240)
                Text("Unlimited").tag(0)
            }
            .font(DS.Fonts.body)
            .foregroundStyle(DS.Colors.text)

            Text("\(screenshotsSize) (\(screenshotsCount))")
                .font(DS.Fonts.mono)
                .foregroundStyle(DS.Colors.textSecondary)

            Divider()

            Text("Text & Descriptions")
                .font(DS.Fonts.body.bold())
                .foregroundStyle(DS.Colors.text)

            Picker("Keep for", selection: Binding(
                get: { settings.textRetentionDays },
                set: { settings.textRetentionDays = $0 }
            )) {
                Text("90 days").tag(90)
                Text("180 days").tag(180)
                Text("365 days").tag(365)
            }
            .font(DS.Fonts.body)
            .foregroundStyle(DS.Colors.text)

            Text("\(dbSize) (\(totalFragments) fragments)")
                .font(DS.Fonts.mono)
                .foregroundStyle(DS.Colors.textSecondary)

            Divider()

            Button("Delete Everything") {
                showDeleteConfirmation = true
            }
            .foregroundStyle(DS.Colors.error)
            .font(DS.Fonts.body)
        }
        .dsCard()
    }

    // MARK: - Model Status

    @ViewBuilder
    private var modelStatusView: some View {
        switch ModelManager.shared.status {
        case .idle:
            Text("Not loaded")
                .font(DS.Fonts.mono)
                .foregroundStyle(DS.Colors.textSecondary)
        case .downloading(let progress):
            HStack(spacing: DS.Spacing.sm) {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text("\(Int(progress * 100))%")
                    .font(DS.Fonts.mono)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
        case .loading:
            Text("Loading...")
                .font(DS.Fonts.mono)
                .foregroundStyle(DS.Colors.accent)
        case .ready:
            Text("Ready")
                .font(DS.Fonts.mono)
                .foregroundStyle(DS.Colors.success)
        case .inferring(let progress):
            if let progress {
                Text(progress.phase == .describing
                     ? "Describing \(progress.current)/\(progress.total)"
                     : "Summarizing \(progress.current)/\(progress.total)")
                    .font(DS.Fonts.mono)
                    .foregroundStyle(DS.Colors.accent)
            } else {
                Text("Inferring…")
                    .font(DS.Fonts.mono)
                    .foregroundStyle(DS.Colors.accent)
            }
        case .error(let msg):
            Text(msg)
                .font(DS.Fonts.mono)
                .foregroundStyle(DS.Colors.error)
                .lineLimit(2)
        }
    }

    // MARK: - Helpers

    private func loadStats() {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file

        let dbBytes = StorageManager.shared.databaseSize()
        dbSize = formatter.string(fromByteCount: dbBytes)
        totalFragments = (try? StorageManager.shared.totalFragmentCount()) ?? 0

        let ssBytes = StorageManager.shared.screenshotsSizeBytes()
        screenshotsSize = formatter.string(fromByteCount: ssBytes)
        screenshotsCount = StorageManager.shared.screenshotsCount()
    }

    private var availableApps: [NSRunningApplication] {
        let selfBundleID = Bundle.main.bundleIdentifier ?? ""
        let excluded = Set(settings.excludedBundleIDs)
        let search = appSearchText.lowercased()

        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular,
                      let id = app.bundleIdentifier,
                      id != selfBundleID,
                      !excluded.contains(id) else { return false }
                if search.isEmpty { return true }
                let name = (app.localizedName ?? id).lowercased()
                return name.contains(search)
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }
}

private struct AppPickerSheet: View {
    let settings: AppSettings
    @Binding var searchText: String
    let availableApps: [NSRunningApplication]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Exclude an App")
                    .font(DS.Fonts.title)
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(DS.Spacing.lg)

            // Search field
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.textSecondary)
                TextField("Filter apps…", text: $searchText)
                    .font(DS.Fonts.body)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(DS.Colors.bg)
            )
            .padding(.horizontal, DS.Spacing.lg)

            Divider()
                .padding(.top, DS.Spacing.md)

            // App list
            if availableApps.isEmpty {
                Spacer()
                Text("No apps found")
                    .font(DS.Fonts.bodySmall)
                    .foregroundStyle(DS.Colors.textSecondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(availableApps, id: \.bundleIdentifier) { app in
                            Button {
                                if let id = app.bundleIdentifier {
                                    settings.exclude(id)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 24, height: 24)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.localizedName ?? "Unknown")
                                            .font(DS.Fonts.body)
                                            .foregroundStyle(DS.Colors.text)
                                        Text(app.bundleIdentifier ?? "")
                                            .font(DS.Fonts.caption)
                                            .foregroundStyle(DS.Colors.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.sm)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 420)
        .background(DS.Colors.surface)
    }
}
