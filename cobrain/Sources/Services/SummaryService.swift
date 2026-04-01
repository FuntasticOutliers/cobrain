import Foundation
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "summary")

final class SummaryService: Sendable {
    static let shared = SummaryService()

    // Use an actor to protect mutable state instead of @MainActor
    private let state = SummaryState()

    private actor SummaryState {
        var task: Task<Void, Never>?
        var isRunning = false

        func setTask(_ t: Task<Void, Never>?) { task = t }
        func getTask() -> Task<Void, Never>? { task }
        func startRunning() -> Bool {
            guard !isRunning else { return false }
            isRunning = true
            return true
        }
        func stopRunning() { isRunning = false }
    }

    func start() {
        Task {
            guard await state.getTask() == nil else { return }
            log.info("Starting summary service (120s interval)")

            let t = Task.detached { [weak self] in
                try? await Task.sleep(for: .seconds(10))

                while !Task.isCancelled {
                    await self?.processUnsummarized()
                    try? await Task.sleep(for: .seconds(120))
                }
            }
            await state.setTask(t)
        }
    }

    func stop() {
        Task {
            await state.getTask()?.cancel()
            await state.setTask(nil)
        }
    }

    private func processUnsummarized() async {
        guard await state.startRunning() else { return }
        defer { Task { await state.stopRunning() } }

        guard await ModelManager.shared.isReady else { return }

        do {
            let fragments = try StorageManager.shared.unsummarizedFragments(limit: 20)
            guard !fragments.isEmpty else { return }

            log.info("Summarizing \(fragments.count, privacy: .public) fragments")

            // Process summaries concurrently in batches of 4
            for batch in fragments.chunked(into: 4) {
                guard !Task.isCancelled else { break }

                await withTaskGroup(of: Void.self) { group in
                    for fragment in batch {
                        group.addTask {
                            await self.summarize(fragment)
                        }
                    }
                }
            }
        } catch {
            log.error("Failed to fetch unsummarized: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func summarize(_ fragment: Fragment) async {
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
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
