import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Factory

@MainActor
struct AssistantViewFactory {
    static func build() -> some View {
        AssistantEntry()
    }
}

// MARK: - Entry

private struct AssistantEntry: View {
    var body: some View {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            AssistantAvailabilityGate()
        } else {
            AssistantUnavailableView(
                message: String(localized: "The assistant requires iOS 26 or later.")
            )
        }
        #else
        AssistantUnavailableView(
            message: String(localized: "The assistant requires a newer version of iOS.")
        )
        #endif
    }
}

// MARK: - Unavailable

struct AssistantUnavailableView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "Assistant Unavailable"), systemImage: "sparkles")
        } description: {
            Text(message)
        }
        .navigationTitle(String(localized: "Assistant"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
extension AssistantUnavailableView {
    static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return String(localized: "This device doesn’t support Apple Intelligence, which the assistant requires.")
        case .appleIntelligenceNotEnabled:
            return String(localized: "Turn on Apple Intelligence in Settings to use the assistant.")
        case .modelNotReady:
            return String(localized: "The on-device model is still preparing. Please try again in a little while.")
        @unknown default:
            return String(localized: "The assistant is currently unavailable on this device.")
        }
    }
}

// MARK: - Availability Gate

@available(iOS 26.0, *)
private struct AssistantAvailabilityGate: View {
    var body: some View {
        switch SystemLanguageModel.default.availability {
        case .available:
            AssistantLoadedView()
        case .unavailable(let reason):
            AssistantUnavailableView(message: AssistantUnavailableView.message(for: reason))
        }
    }
}

@available(iOS 26.0, *)
private struct AssistantLoadedView: View {
    @StateObject private var viewModel = AssistantViewModel()

    var body: some View {
        AssistantContentView(viewModel: viewModel)
    }
}

// MARK: - Content

@available(iOS 26.0, *)
struct AssistantContentView<ViewModel: AssistantViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @FocusState private var isInputFocused: Bool

    private static var typingIndicatorID: String { "assistant.typing.indicator" }

    var body: some View {
        VStack(spacing: 0) {
            buildMessages()
            buildErrorBanner()
            buildInputBar()
        }
        .navigationTitle(String(localized: "Assistant"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { buildToolbar() }
        .task { viewModel.prewarm() }
    }

    // MARK: Messages

    private func buildMessages() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.uiState.messages.isEmpty {
                        buildEmptyState()
                    }

                    ForEach(viewModel.uiState.messages) { message in
                        AssistantMessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.uiState.isResponding {
                        buildTypingIndicator()
                            .id(Self.typingIndicatorID)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.uiState.messages) {
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.uiState.isResponding) {
                scrollToBottom(proxy)
            }
        }
    }

    private func buildEmptyState() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text(String(localized: "Ask about your apps"))
                .font(.headline)

            Text(String(localized: "Read-only for now — I can answer questions and explain things, but I can’t change anything in App Store Connect yet."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func buildTypingIndicator() -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text(String(localized: "Thinking…"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Error

    @ViewBuilder
    private func buildErrorBanner() -> some View {
        if let error = viewModel.uiState.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
        }
    }

    // MARK: Input

    private func buildInputBar() -> some View {
        HStack(spacing: 10) {
            TextField(
                String(localized: "Message"),
                text: $viewModel.uiState.inputText,
                axis: .vertical
            )
            .lineLimit(1...5)
            .textFieldStyle(.plain)
            .focused($isInputFocused)
            .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
            }
            .disabled(isSendDisabled)
            .accessibilityLabel(String(localized: "Send"))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var isSendDisabled: Bool {
        viewModel.uiState.isResponding
            || viewModel.uiState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        isInputFocused = false
        Task { await viewModel.sendCurrentInput() }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .destructive) {
                viewModel.clearConversation()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(viewModel.uiState.messages.isEmpty || viewModel.uiState.isResponding)
            .accessibilityLabel(String(localized: "Clear Conversation"))
        }
    }

    // MARK: Helpers

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if viewModel.uiState.isResponding {
                proxy.scrollTo(Self.typingIndicatorID, anchor: .bottom)
            } else if let last = viewModel.uiState.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

#endif
