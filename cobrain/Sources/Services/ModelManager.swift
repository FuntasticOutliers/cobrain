import Foundation
import MLXVLM
import MLXLMCommon
import CoreImage
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "model")

/// Actor that runs VLM inference off the main thread.
private actor InferenceRunner {
    private var describeSession: ChatSession?
    private weak var currentContainer: ModelContainer?

    func describe(
        container: ModelContainer,
        image: CGImage,
        appName: String,
        windowTitle: String?,
        url: String?
    ) async throws -> String {
        var context = appName
        if let title = windowTitle { context += " — \(title)" }
        if let url { context += " (\(url))" }

        let prompt = """
        Describe what the user is doing in this screenshot from \(context). \
        Be concise — 2-3 sentences. Focus on the activity and content, not UI chrome.
        """

        let ciImage = CIImage(cgImage: image)

        // Reuse the ChatSession if the container hasn't changed
        if describeSession == nil || currentContainer !== container {
            describeSession = ChatSession(
                container,
                generateParameters: GenerateParameters(maxTokens: 200, temperature: 0.3)
            )
            currentContainer = container
        }

        return try await describeSession!.respond(to: prompt, image: .ciImage(ciImage))
    }

    func complete(
        container: ModelContainer,
        system: String,
        user: String,
        maxTokens: Int
    ) async throws -> String {
        let session = ChatSession(
            container,
            instructions: system,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.3)
        )
        return try await session.respond(to: user)
    }

    func resetSession() {
        describeSession = nil
        currentContainer = nil
    }
}

@Observable
@MainActor
final class ModelManager {
    static let shared = ModelManager()

    enum Status: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case inferring
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var container: ModelContainer?
    private(set) var loadedModelID: String?

    private let inference = InferenceRunner()

    var isReady: Bool { status == .ready || status == .inferring }

    /// Ensures the model is loaded and ready. Loads on demand if idle.
    func ensureReady() async {
        switch status {
        case .ready, .inferring:
            return
        case .downloading, .loading:
            await waitUntilLoaded()
            return
        case .idle, .error:
            await loadModel()
        }
    }

    func loadModel() async {
        guard status == .idle || {
            if case .error = status { return true }
            return false
        }() else { return }

        let modelID = AppSettings.shared.modelID
        log.info("Starting model load: \(modelID, privacy: .public)")
        status = .downloading(0)

        do {
            let config = ModelConfiguration(id: modelID)
            let loaded = try await VLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    self.status = .downloading(progress.fractionCompleted)
                }
            }

            status = .loading
            self.container = loaded
            self.loadedModelID = modelID
            status = .ready
            log.info("Model loaded successfully")
        } catch {
            log.error("Model load failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
        }
    }

    func reloadModel() async {
        unloadModel()
        await inference.resetSession()
        await loadModel()
    }

    /// Unload the model to free memory.
    func unloadModel() {
        container = nil
        loadedModelID = nil
        status = .idle
        log.info("Model unloaded")
    }

    /// Describe a screenshot using the VLM. Runs inference off the main thread.
    func describe(
        image: CGImage,
        appName: String,
        windowTitle: String?,
        url: String?
    ) async throws -> String {
        guard let container else { throw ModelError.notLoaded }
        status = .inferring
        defer { if status == .inferring { status = .ready } }
        return try await inference.describe(
            container: container,
            image: image,
            appName: appName,
            windowTitle: windowTitle,
            url: url
        )
    }

    /// Generate a single text completion. Runs inference off the main thread.
    func complete(system: String, user: String, maxTokens: Int = 256) async throws -> String {
        guard let container else { throw ModelError.notLoaded }
        status = .inferring
        defer { if status == .inferring { status = .ready } }
        return try await inference.complete(
            container: container,
            system: system,
            user: user,
            maxTokens: maxTokens
        )
    }

    /// Stream a text response. Used for chat.
    func stream(system: String, user: String, maxTokens: Int = 512) throws -> AsyncThrowingStream<String, Error> {
        guard let container else { throw ModelError.notLoaded }
        status = .inferring

        let session = ChatSession(
            container,
            instructions: system,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.7)
        )
        return session.streamResponse(to: user)
    }

    /// Called when streaming completes to transition back from .inferring.
    func streamDidFinish() {
        if status == .inferring { status = .ready }
    }

    /// Wait for an in-progress load to complete.
    private func waitUntilLoaded() async {
        // Poll briefly — the load is already running on another task
        for _ in 0..<600 { // up to ~60 seconds
            try? await Task.sleep(for: .milliseconds(100))
            switch status {
            case .ready, .inferring: return
            case .error, .idle: return
            case .downloading, .loading: continue
            }
        }
    }

    enum ModelError: Error, LocalizedError {
        case notLoaded

        var errorDescription: String? {
            switch self {
            case .notLoaded: return "Model not loaded"
            }
        }
    }
}
