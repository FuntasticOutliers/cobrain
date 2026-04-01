import SwiftUI
import AppKit
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "replay")

struct ReplayView: View {
    @State private var selectedDate: Date = Date()
    @State private var fragments: [Fragment] = []
    @State private var currentIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var playbackSpeed: Double = 1.0
    @State private var timer: Timer?

    private let speeds: [Double] = [0.5, 1, 2, 4]

    var body: some View {
        VStack(spacing: 0) {
            dateHeader
            Divider()

            if fragments.isEmpty {
                emptyState
            } else {
                replayContent
            }
        }
        .onAppear { loadFragments() }
        .onChange(of: selectedDate) { _, _ in
            stopPlayback()
            loadFragments()
        }
        .onDisappear { stopPlayback() }
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: DS.Spacing.xxs) {
                Text(dayLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                Text("\(fragments.count) screenshots")
                    .font(DS.Fonts.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
            }

            Spacer()

            Button {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                if tomorrow <= Date() {
                    selectedDate = tomorrow
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isToday ? DS.Colors.border : DS.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isToday)
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.md)
    }

    // MARK: - Replay Content

    private var replayContent: some View {
        VStack(spacing: 0) {
            // Screenshot display
            ZStack {
                DS.Colors.surface

                if let fragment = currentFragment,
                   let path = fragment.imagePath {
                    let url = StorageManager.screenshotURL(for: path)
                    AsyncImageView(url: url)
                } else {
                    VStack(spacing: DS.Spacing.md) {
                        Image(systemName: "photo")
                            .font(.system(size: 36, weight: .thin))
                            .foregroundStyle(DS.Colors.textSecondary)
                        Text("No screenshot saved")
                            .font(DS.Fonts.body)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Metadata overlay
            if let fragment = currentFragment {
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: fragment.appIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.accent)

                    Text(fragment.appName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Colors.text)

                    if let title = fragment.windowTitle, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(timeString(for: fragment))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Colors.surface)
            }

            Divider()

            // Playback controls
            playbackControls
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        VStack(spacing: DS.Spacing.sm) {
            // Scrubber
            Slider(
                value: Binding(
                    get: { Double(currentIndex) },
                    set: { currentIndex = Int($0) }
                ),
                in: 0...Double(max(fragments.count - 1, 0)),
                step: 1
            )
            .tint(DS.Colors.accent)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)

            HStack(spacing: DS.Spacing.lg) {
                // Frame counter
                Text("\(currentIndex + 1) / \(fragments.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .frame(width: 80, alignment: .leading)

                Spacer()

                // Previous
                Button {
                    stopPlayback()
                    if currentIndex > 0 { currentIndex -= 1 }
                } label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Colors.text)
                }
                .buttonStyle(.plain)
                .disabled(currentIndex == 0)

                // Play / Pause
                Button {
                    if isPlaying { stopPlayback() } else { startPlayback() }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DS.Colors.accent)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                // Next
                Button {
                    stopPlayback()
                    if currentIndex < fragments.count - 1 { currentIndex += 1 }
                } label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Colors.text)
                }
                .buttonStyle(.plain)
                .disabled(currentIndex >= fragments.count - 1)

                Spacer()

                // Speed picker
                Menu {
                    ForEach(speeds, id: \.self) { speed in
                        Button {
                            playbackSpeed = speed
                            if isPlaying {
                                stopPlayback()
                                startPlayback()
                            }
                        } label: {
                            HStack {
                                Text(speedLabel(speed))
                                if speed == playbackSpeed {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(speedLabel(playbackSpeed))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 50)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.sm)
        }
        .background(DS.Colors.bg)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Image(systemName: "play.slash")
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(DS.Colors.textSecondary)
            Text("No screenshots for \(dayLabel.lowercased())")
                .font(DS.Fonts.body)
                .foregroundStyle(DS.Colors.textSecondary)
            Text("Screenshots are saved automatically going forward.")
                .font(DS.Fonts.caption)
                .foregroundStyle(DS.Colors.textSecondary.opacity(0.7))
            Spacer()
        }
    }

    // MARK: - Playback Logic

    private func startPlayback() {
        guard !fragments.isEmpty else { return }
        isPlaying = true
        let interval = 1.0 / playbackSpeed
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                if currentIndex < fragments.count - 1 {
                    currentIndex += 1
                } else {
                    stopPlayback()
                }
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Data

    private func loadFragments() {
        let day = Fragment.makeDay(from: selectedDate)
        do {
            let allFragments = try StorageManager.shared.fragmentsForDay(day)
            // Only include fragments that have a saved screenshot
            fragments = allFragments.filter { $0.imagePath != nil }
            currentIndex = 0
            log.info("Loaded \(fragments.count) screenshots for replay on \(day)")
        } catch {
            log.error("Failed to load replay data: \(error.localizedDescription)")
            fragments = []
        }
    }

    private var currentFragment: Fragment? {
        guard !fragments.isEmpty, currentIndex < fragments.count else { return nil }
        return fragments[currentIndex]
    }

    private var dayLabel: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private func timeString(for fragment: Fragment) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(fragment.capturedAt))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: date)
    }

    private func speedLabel(_ speed: Double) -> String {
        if speed == 0.5 { return "0.5x" }
        return "\(Int(speed))x"
    }
}

// MARK: - Async Image View (loads from file URL)

struct AsyncImageView: View {
    let url: URL
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .onAppear { loadImage() }
        .onChange(of: url) { _, _ in loadImage() }
    }

    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let img = NSImage(contentsOf: url)
            DispatchQueue.main.async {
                nsImage = img
            }
        }
    }
}
