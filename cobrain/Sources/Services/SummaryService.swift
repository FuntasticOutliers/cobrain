import Foundation
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "summary")

@MainActor
final class SummaryService {
    static let shared = SummaryService()

    private var task: Task<Void, Never>?
    private var isRunning = false

    func start() {
        guard task == nil else { return }
        log.info("Starting summary service (120s interval)")

        task = Task { [weak self] in
            // Initial delay
            try? await Task.sleep(for: .seconds(10))

            while !Task.isCancelled {
                await self?.processUnsummarized()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func processUnsummarized() async {
        guard !isRunning else { return }
        guard ModelManager.shared.isReady else { return }
        isRunning = true
        defer { isRunning = false }

        do {
            let fragments = try StorageManager.shared.unsummarizedFragments(limit: 20)
            guard !fragments.isEmpty else { return }

            log.info("Summarizing \(fragments.count, privacy: .public) fragments")

            for fragment in fragments {
                guard !Task.isCancelled else { break }

                let contentPreview = String(fragment.content.prefix(1500))
                let prompt = """
                Summarize this text captured from \(fragment.appName)\
                \(fragment.windowTitle.map { " (\($0))" } ?? ""). \
                Be concise — 1-2 sentences. Just the summary, nothing else.

                Text:
                \(contentPreview)
                """

                do {
                    let summary = try await ModelManager.shared.complete(
                        system: "You are a concise summarizer. Output only the summary, no preamble.",
                        user: prompt,
                        maxTokens: 100
                    )

                    if !summary.isEmpty, let id = fragment.id {
                        try StorageManager.shared.updateFragmentSummary(id: id, summary: summary)
                        log.info("Summarized fragment #\(id, privacy: .public): \(summary.prefix(80), privacy: .public)")
                    }
                } catch {
                    log.error("Summary failed for #\(fragment.id ?? -1, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            log.error("Failed to fetch unsummarized: \(error.localizedDescription, privacy: .public)")
        }
    }
}
