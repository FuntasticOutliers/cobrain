import SwiftUI
import AppKit
import Sparkle
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "app")

@main
struct CobrainApp: App {
    private let settings = AppSettings.shared
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Cobrain", id: "main") {
            MainView(settings: settings, updater: updaterController.updater)
                .preferredColorScheme(settings.theme.colorScheme)
                .onAppear {
                    if settings.hasCompletedOnboarding {
                        CaptureScheduler.shared.start()
                        BatchInferenceCoordinator.shared.start()
                        ModelManager.shared.refreshPendingCount()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView(settings: settings, updater: updaterController.updater) {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } onSearch: {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .focusSearch, object: nil)
            }
        } label: {
            Image(systemName: settings.captureEnabled ? "brain.filled.head.profile" : "brain.head.profile")
        }
    }

}

// MARK: - Menu Bar View

struct MenuBarView: View {
    let settings: AppSettings
    let updater: SPUUpdater
    let onOpen: () -> Void
    let onSearch: () -> Void

    @State private var todayCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onSearch()
            } label: {
                Label("Search...", systemImage: "magnifyingglass")
            }

            Divider()

            HStack {
                Circle()
                    .fill(settings.captureEnabled ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(settings.captureEnabled ? "Capturing" : "Paused")
                    .font(.system(size: 12))
                Spacer()
                Text("\(todayCount) today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            Button("Open Cobrain") { onOpen() }

            Button("Check for Updates...") { updater.checkForUpdates() }

            Divider()

            Button("Quit") {
                    StorageManager.shared.checkpoint()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
        }
        .onAppear {
            todayCount = (try? StorageManager.shared.todayFragmentCount()) ?? 0
        }
    }
}

// MARK: - Main View

struct MainView: View {
    let settings: AppSettings
    let updater: SPUUpdater

    var body: some View {
        if settings.hasCompletedOnboarding {
            HomeView(settings: settings, updater: updater)
                .frame(minWidth: 700, minHeight: 500)
        } else {
            OnboardingView(settings: settings) {
                CaptureScheduler.shared.start()
            }
            .frame(width: 480, height: 420)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let focusSearch = Notification.Name("focusSearch")
}
