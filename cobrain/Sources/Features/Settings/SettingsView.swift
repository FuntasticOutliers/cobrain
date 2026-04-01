import SwiftUI
import Sparkle

struct SettingsView: View {
    let settings: AppSettings
    let updater: SPUUpdater

    @State private var dbSize: String = "..."
    @State private var totalFragments: Int = 0
    @State private var showDeleteConfirmation = false
    @State private var showingAppPicker = false
    @State private var appSearchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Capture section
                section("CAPTURE") {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
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

                        Toggle("Enable capture", isOn: Binding(
                            get: { settings.captureEnabled },
                            set: { settings.captureEnabled = $0 }
                        ))
                        .font(DS.Fonts.body)
                        .foregroundStyle(DS.Colors.text)
                    }
                }

                // Model section
                section("MODEL") {
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
                }

                // Excluded apps section
                section("EXCLUDED APPS") {
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
                }

                // Storage section
                section("STORAGE") {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        HStack {
                            Text("Keep fragments for")
                                .font(DS.Fonts.body)
                                .foregroundStyle(DS.Colors.text)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { settings.retentionDays },
                                set: { settings.retentionDays = $0 }
                            )) {
                                Text("30 days").tag(30)
                                Text("60 days").tag(60)
                                Text("90 days").tag(90)
                                Text("180 days").tag(180)
                                Text("365 days").tag(365)
                            }
                            .frame(width: 120)
                        }

                        HStack {
                            Text("Database size")
                                .font(DS.Fonts.body)
                                .foregroundStyle(DS.Colors.text)
                            Spacer()
                            Text(dbSize)
                                .font(DS.Fonts.mono)
                                .foregroundStyle(DS.Colors.textSecondary)
                        }

                        HStack {
                            Text("Total fragments")
                                .font(DS.Fonts.body)
                                .foregroundStyle(DS.Colors.text)
                            Spacer()
                            Text("\(totalFragments)")
                                .font(DS.Fonts.mono)
                                .foregroundStyle(DS.Colors.textSecondary)
                        }

                        Button("Delete All Data") {
                            showDeleteConfirmation = true
                        }
                        .foregroundStyle(DS.Colors.error)
                        .font(DS.Fonts.body)
                    }
                }

                // Appearance section
                section("APPEARANCE") {
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
                }

                // About
                section("ABOUT") {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        Text("Cobrain v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")")
                            .font(DS.Fonts.bodySmall)
                            .foregroundStyle(DS.Colors.textSecondary)

                        Button("Check for Updates...") {
                            updater.checkForUpdates()
                        }
                        .font(DS.Fonts.body)

                        Toggle("Automatically check for updates", isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.automaticallyChecksForUpdates = $0 }
                        ))
                        .font(DS.Fonts.body)
                        .foregroundStyle(DS.Colors.text)
                    }
                }
            }
            .padding(DS.Spacing.xl)
        }
        .frame(maxWidth: 500)
        .onAppear { loadStats() }
        .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                try? StorageManager.shared.purgeOlderThan(days: 0)
                loadStats()
            }
        } message: {
            Text("This will permanently delete all captured fragments. This cannot be undone.")
        }
    }

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

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(title)
                .font(DS.Fonts.sectionHeader)
                .foregroundStyle(DS.Colors.textSecondary)
            content()
                .dsCard()
        }
    }

    private func loadStats() {
        let bytes = StorageManager.shared.databaseSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        dbSize = formatter.string(fromByteCount: bytes)
        totalFragments = (try? StorageManager.shared.totalFragmentCount()) ?? 0
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
