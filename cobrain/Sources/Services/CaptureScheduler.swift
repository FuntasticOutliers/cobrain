import AppKit
import Foundation
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "capture")

final class CaptureScheduler {
    static let shared = CaptureScheduler()

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "dev.cobrain.capture", qos: .utility)
    private var workspaceObservers: [NSObjectProtocol] = []

    private let screenCapture = ScreenCaptureService.shared
    private let windowMetadata = WindowMetadataService.shared
    private let contextService = ContextDetectionService.shared
    private let changeDetection = ChangeDetectionService.shared
    private let storage = StorageManager.shared
    private let settings = AppSettings.shared

    private var isPaused = false
    private var isProcessing = false

    // Adaptive interval state
    private var previousImage: CGImage?
    private var currentInterval: Int = 0
    private var consecutiveSkips: Int = 0

    func start() {
        guard timer == nil else { return }
        currentInterval = settings.captureIntervalSeconds
        log.info("Starting capture scheduler (interval: \(self.currentInterval)s, change threshold: \(self.settings.changeDetectionThreshold))")

        scheduleTimer(interval: currentInterval, initialDelay: 2)
        registerObservers()
    }

    func stop() {
        log.info("Stopping capture scheduler")
        timer?.cancel()
        timer = nil
        previousImage = nil
        consecutiveSkips = 0
        currentInterval = settings.captureIntervalSeconds
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    // MARK: - Timer Management

    private func scheduleTimer(interval: Int, initialDelay: Int? = nil) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(
            deadline: .now() + .seconds(initialDelay ?? interval),
            repeating: .seconds(interval)
        )
        t.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.capture() }
        }
        t.resume()
        timer = t
        currentInterval = interval
    }

    /// Increase the capture interval (back off) when no change is detected.
    private func backOff() {
        consecutiveSkips += 1
        let baseInterval = settings.captureIntervalSeconds
        let maxInterval = settings.maxCaptureIntervalSeconds
        // Double the interval for each consecutive skip, capped at maxInterval
        let newInterval = min(baseInterval * (1 << min(consecutiveSkips, 4)), maxInterval)
        if newInterval != currentInterval {
            log.debug("Backing off: \(self.currentInterval)s → \(newInterval)s (skips: \(self.consecutiveSkips))")
            scheduleTimer(interval: newInterval)
        }
    }

    /// Reset the capture interval to the base rate.
    private func resetInterval() {
        let baseInterval = settings.captureIntervalSeconds
        consecutiveSkips = 0
        if currentInterval != baseInterval {
            log.debug("Resetting interval: \(self.currentInterval)s → \(baseInterval)s")
            scheduleTimer(interval: baseInterval)
        }
    }

    // MARK: - Capture

    private func capture() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        guard settings.captureEnabled, !isPaused else { return }
        guard WindowMetadataService.isAccessibilityGranted() else {
            log.warning("Accessibility not granted, skipping capture")
            return
        }

        guard let context = contextService.frontmostContext() else { return }
        guard !settings.isExcluded(context.bundleIdentifier) else {
            log.debug("Excluded app: \(context.appName) (\(context.bundleIdentifier))")
            return
        }

        log.debug("Capturing from \(context.appName, privacy: .public) (\(context.bundleIdentifier, privacy: .public))")

        // Get window metadata (title + URL) via lightweight AX reads
        let meta = windowMetadata.metadata(for: context.pid, bundleID: context.bundleIdentifier)

        // Skip private/incognito browser windows
        if let title = meta.windowTitle,
           WindowMetadataService.isPrivateBrowsing(title: title, bundleID: context.bundleIdentifier) {
            log.debug("Skipping private browsing window: \(context.appName, privacy: .public)")
            return
        }

        // Screenshot the frontmost window
        let image: CGImage
        do {
            guard let img = try await screenCapture.captureWindow(pid: context.pid) else {
                log.debug("No window found for \(context.appName, privacy: .public)")
                return
            }
            image = img
        } catch {
            log.error("Screenshot error for \(context.appName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        // Change detection — skip VLM if screen hasn't meaningfully changed
        if let prev = previousImage,
           let diff = changeDetection.difference(between: image, and: prev) {
            if diff < settings.changeDetectionThreshold {
                log.debug("Screen unchanged (diff: \(String(format: "%.3f", diff))), skipping VLM")
                backOff()
                return
            }
            log.debug("Screen changed (diff: \(String(format: "%.3f", diff))), running VLM")
        }

        // Screen changed — reset adaptive interval and store current image
        previousImage = image
        resetInterval()

        // Save screenshot to disk
        let now = Int(Date().timeIntervalSince1970)
        let day = Fragment.makeDay()
        guard let savedImagePath = storage.saveScreenshot(image, day: day, timestamp: now) else {
            log.error("Failed to save screenshot for \(context.appName, privacy: .public)")
            return
        }

        // Queue for batch inference (VLM runs later)
        storage.savePendingCapture(
            imagePath: savedImagePath,
            bundleIdentifier: context.bundleIdentifier,
            appName: context.appName,
            windowTitle: meta.windowTitle,
            url: meta.browserURL,
            appCategory: context.category.rawValue
        )

        log.info("Queued pending capture from \(context.appName, privacy: .public), window: \(meta.windowTitle ?? "nil", privacy: .public)")
        await ModelManager.shared.refreshPendingCount()
    }

    // MARK: - System Events

    private func registerObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            nc.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                // App switch — clear previous image to force VLM on new context
                self.previousImage = nil
                self.resetInterval()
                Task { await self.capture() }
            }
        )

        workspaceObservers.append(
            nc.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil, queue: nil
            ) { [weak self] _ in
                log.info("System sleeping, pausing capture")
                self?.isPaused = true
            }
        )
        workspaceObservers.append(
            nc.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil, queue: nil
            ) { [weak self] _ in
                log.info("Screen locked, pausing capture")
                self?.isPaused = true
            }
        )

        workspaceObservers.append(
            nc.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil, queue: nil
            ) { [weak self] _ in
                log.info("System woke, resuming capture in 2s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.isPaused = false
                    self?.previousImage = nil // Force fresh capture after wake
                }
            }
        )
        workspaceObservers.append(
            nc.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil, queue: nil
            ) { [weak self] _ in
                log.info("Screen unlocked, resuming capture")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.isPaused = false
                    self?.previousImage = nil // Force fresh capture after unlock
                }
            }
        )
    }
}
