import Foundation
import ImageIO
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "batch")

@MainActor
final class BatchInferenceCoordinator {
    static let shared = BatchInferenceCoordinator()

    private var timer: Task<Void, Never>?
    private var isProcessing = false

    /// How often the batch timer fires (seconds).
    private let batchInterval: TimeInterval = 300 // 5 minutes

    func start() {
        guard timer == nil else { return }
        log.info("Starting batch inference coordinator (\(Int(self.batchInterval))s interval)")

        timer = Task(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.batchInterval ?? 300))
                guard !Task.isCancelled else { break }
                await self?.processBatch()
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Process all pending captures now.
    func flushNow() async {
        await processBatch()
    }

    // MARK: - Batch Processing

    private func processBatch() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let pending: [PendingCapture]
        do {
            pending = try StorageManager.shared.fetchPendingCaptures(limit: 50)
        } catch {
            log.error("Failed to fetch pending captures: \(error.localizedDescription)")
            return
        }

        guard !pending.isEmpty else {
            log.debug("No pending captures to process")
            return
        }

        let total = pending.count
        log.info("Processing batch of \(total) pending captures")

        // Load model
        await ModelManager.shared.ensureReady()
        guard ModelManager.shared.isReady else {
            log.error("Model failed to load, skipping batch")
            return
        }

        let dedup = DeduplicationService.shared
        let storage = StorageManager.shared
        var processed = 0

        for (index, capture) in pending.enumerated() {
            guard let id = capture.id else { continue }

            // Report progress
            ModelManager.shared.setBatchProgress(.init(
                current: index + 1, total: total, phase: .describing
            ))

            // Load image from disk
            let imageURL = StorageManager.screenshotURL(for: capture.imagePath)
            guard let image = Self.loadImage(from: imageURL) else {
                log.warning("Failed to load image for pending capture \(id), deleting")
                try? storage.deletePendingCapture(id: id)
                continue
            }

            // Downsample for VLM
            let vlmImage = ScreenCaptureService.downsampleForVLM(image) ?? image

            // Run VLM inference
            let description: String
            do {
                description = try await ModelManager.shared.describe(
                    image: vlmImage,
                    appName: capture.appName,
                    windowTitle: capture.windowTitle,
                    url: capture.url
                )
                guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    log.debug("Empty description for pending capture \(id)")
                    try? storage.deletePendingCapture(id: id)
                    continue
                }
            } catch {
                log.error("VLM error for pending capture \(id): \(error.localizedDescription)")
                continue
            }

            // Dedup check
            let dedupResult = dedup.check(
                content: description,
                bundleID: capture.bundleIdentifier,
                windowTitle: capture.windowTitle
            )
            guard case .newFragment = dedupResult else {
                log.debug("Duplicate description for pending capture \(id)")
                try? storage.deletePendingCapture(id: id)
                continue
            }

            // Save fragment
            let hash = DeduplicationService.hash(description)
            storage.saveFragment(
                content: description,
                contentHash: hash,
                focusedText: nil,
                bundleIdentifier: capture.bundleIdentifier,
                appName: capture.appName,
                windowTitle: capture.windowTitle,
                url: capture.url,
                appCategory: capture.appCategory,
                summary: description,
                imagePath: capture.imagePath
            )

            // Remove from pending queue
            try? storage.deletePendingCapture(id: id)
            processed += 1
            ModelManager.shared.refreshPendingCount()
        }

        log.info("Batch complete: \(processed)/\(pending.count) captures processed")

        // Piggyback: let SummaryService process while model is hot
        await SummaryService.shared.processIfNeeded()

        // Unload model
        ModelManager.shared.unloadModel()
        log.info("Model unloaded after batch")
    }

    // MARK: - Image Loading

    private static func loadImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
