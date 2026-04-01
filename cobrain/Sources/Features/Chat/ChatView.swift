import SwiftUI
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "chat")

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Model status
            if !viewModel.modelReady {
                modelStatusBar
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: DS.Spacing.md) {
                        if viewModel.messages.isEmpty {
                            chatEmptyState
                        }

                        ForEach(viewModel.messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }

                        if viewModel.isGenerating {
                            HStack(spacing: DS.Spacing.sm) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(viewModel.toolStatus ?? "Thinking...")
                                    .font(DS.Fonts.caption)
                                    .foregroundStyle(DS.Colors.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                            .id("loading")
                        }
                    }
                    .padding(.vertical, DS.Spacing.md)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation {
                        if let lastId = viewModel.messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: DS.Spacing.sm) {
                TextField("Ask about your memory...", text: $input)
                    .font(DS.Fonts.body)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit { send() }
                    .disabled(viewModel.isGenerating || !viewModel.modelReady)

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isGenerating
                            ? DS.Colors.border
                            : DS.Colors.accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isGenerating)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
        .onAppear {
            inputFocused = true
            Task { await viewModel.ensureModelLoaded() }
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        Task { await viewModel.send(text) }
    }

    // MARK: - Model Status

    private var modelStatusBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            switch viewModel.modelStatus {
            case .downloading(let progress):
                ProgressView(value: progress)
                    .frame(width: 100)
                Text("Downloading model... \(Int(progress * 100))%")
                    .font(DS.Fonts.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
            case .loading:
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading model...")
                    .font(DS.Fonts.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(DS.Colors.error)
                Text(msg)
                    .font(DS.Fonts.caption)
                    .foregroundStyle(DS.Colors.error)
                    .lineLimit(1)
            default:
                ProgressView()
                    .scaleEffect(0.7)
                Text("Preparing model...")
                    .font(DS.Fonts.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Colors.surface)
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
                .frame(height: 60)

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(DS.Colors.textSecondary)

            Text("Ask your memory")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Colors.text)

            VStack(spacing: DS.Spacing.xs) {
                Text("\"What was that Slack thread about auth?\"")
                Text("\"What did I read about deployment today?\"")
                Text("\"Find that code snippet with validateToken\"")
            }
            .font(DS.Fonts.bodySmall)
            .foregroundStyle(DS.Colors.textSecondary)
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: DS.Spacing.xxs) {
                Text(message.content)
                    .font(DS.Fonts.body)
                    .foregroundStyle(message.role == .user ? .white : DS.Colors.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .fill(message.role == .user ? DS.Colors.accent : DS.Colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .stroke(message.role == .user ? Color.clear : DS.Colors.border, lineWidth: 0.5)
                    )

                if case .tool(let status) = message.role {
                    HStack(spacing: DS.Spacing.xxs) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9))
                        Text(status)
                            .font(DS.Fonts.captionSmall)
                    }
                    .foregroundStyle(DS.Colors.textSecondary)
                }
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role: Equatable {
        case user
        case assistant
        case tool(String)
    }
}
