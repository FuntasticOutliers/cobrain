import Foundation
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "chatvm")

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var isGenerating = false
    var toolStatus: String?
    var modelReady: Bool { ModelManager.shared.isReady }
    var modelStatus: ModelManager.Status { ModelManager.shared.status }

    private let storage = StorageManager.shared

    func ensureModelLoaded() async {
        if !ModelManager.shared.isReady {
            await ModelManager.shared.loadModel()
        }
    }

    func send(_ text: String) async {
        messages.append(ChatMessage(role: .user, content: text))
        isGenerating = true
        toolStatus = nil

        defer { isGenerating = false; toolStatus = nil }

        toolStatus = "Searching fragments..."
        let context = buildContext(for: text)
        log.info("Context built: \(context.count, privacy: .public) chars")

        let totalCount = (try? storage.totalFragmentCount()) ?? 0
        let today = Fragment.makeDay()

        let systemPrompt = """
        You are a helpful assistant called Cobrain. You answer questions using ONLY the captured text fragments provided below. \
        These fragments were automatically captured from the user's screen.

        RULES:
        - Answer ONLY based on the fragments below. Do not make up information.
        - If the fragments contain relevant information, summarize and reference it.
        - If no fragments are relevant, say "I didn't find anything about that in your captured fragments."
        - Be concise and direct.
        - Today's date: \(today). Total fragments: \(totalCount).

        --- CAPTURED FRAGMENTS ---
        \(context)
        --- END FRAGMENTS ---
        """

        do {
            toolStatus = "Thinking..."

            let stream = try ModelManager.shared.stream(
                system: systemPrompt,
                user: text,
                maxTokens: 512
            )

            var response = ""
            let assistantMsg = ChatMessage(role: .assistant, content: "")
            messages.append(assistantMsg)
            let msgIndex = messages.count - 1

            for try await chunk in stream {
                response += chunk
                messages[msgIndex] = ChatMessage(role: .assistant, content: response)
            }

            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            messages[msgIndex] = ChatMessage(role: .assistant, content: trimmed.isEmpty ? "I couldn't generate a response." : trimmed)
            log.info("Chat response: \(trimmed.prefix(200), privacy: .public)")
        } catch {
            log.error("Chat generation error: \(error.localizedDescription, privacy: .public)")
            messages.append(ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
        }
    }

    // MARK: - Context Building

    private func buildContext(for query: String) -> String {
        var allFragments: [Fragment] = []

        // Strategy 1: FTS5 search with individual keywords
        let keywords = extractKeywords(from: query)
        log.info("Search keywords: \(keywords.joined(separator: ", "), privacy: .public)")

        for keyword in keywords {
            if let results = try? storage.search(query: "\(keyword)*", limit: 5) {
                for r in results {
                    if !allFragments.contains(where: { $0.id == r.fragment.id }) {
                        allFragments.append(r.fragment)
                    }
                }
            }
        }

        // Strategy 2: Search by app name if mentioned
        let appNames = ["chrome", "safari", "slack", "whatsapp", "vscode", "code", "terminal",
                        "mail", "gmail", "notion", "discord", "telegram", "xcode", "figma", "arc"]
        for app in appNames {
            if query.localizedCaseInsensitiveContains(app) {
                if let results = try? storage.search(query: app, limit: 5) {
                    for r in results {
                        if !allFragments.contains(where: { $0.id == r.fragment.id }) {
                            allFragments.append(r.fragment)
                        }
                    }
                }
                if let appFragments = try? storage.fragmentsByAppName(app, limit: 5) {
                    for f in appFragments {
                        if !allFragments.contains(where: { $0.id == f.id }) {
                            allFragments.append(f)
                        }
                    }
                }
            }
        }

        // Strategy 3: Always include recent fragments for "what did I do" type questions
        if let recent = try? storage.recentFragments(limit: 10) {
            for f in recent {
                if !allFragments.contains(where: { $0.id == f.id }) {
                    allFragments.append(f)
                }
            }
        }

        log.info("Total context fragments: \(allFragments.count, privacy: .public)")

        if allFragments.isEmpty {
            return "No fragments captured yet."
        }

        let lines: [String] = allFragments.prefix(20).map { f in
            let time = f.relativeTime
            let app = f.appName
            let title = f.windowTitle ?? ""
            let summary = f.summary ?? String(f.content.prefix(400))
            return "[\(time)] App: \(app) | Window: \(title)\n\(summary)"
        }

        return lines.joined(separator: "\n\n")
    }

    private func extractKeywords(from query: String) -> [String] {
        let stopWords: Set<String> = [
            "what", "did", "the", "and", "is", "was", "were", "do", "does",
            "how", "when", "where", "who", "which", "that", "this", "in", "on",
            "at", "to", "for", "of", "with", "about", "from", "my", "me", "can", "you",
            "tell", "show", "find", "search", "look", "get", "see", "read", "today",
            "yesterday", "recently", "last", "have", "has", "had", "been", "be", "are",
            "am", "any", "some", "there", "their", "they", "we", "our", "your", "it",
        ]

        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 && !stopWords.contains($0) }

        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }
}
