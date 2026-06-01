import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Models

/// A single message in the assistant conversation.
struct AssistantMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

// MARK: - UiState

struct AssistantUiState {
    var messages: [AssistantMessage] = []
    var inputText: String = ""
    var isResponding: Bool = false
    var errorMessage: String?
}

#if canImport(FoundationModels)

// MARK: - Protocol

@available(iOS 26.0, *)
@MainActor
protocol AssistantViewModelProtocol: ObservableObject {
    var uiState: AssistantUiState { get set }
    func prewarm()
    func sendCurrentInput() async
    func clearConversation()
}

// MARK: - Implementation

/// Phase 0 assistant: a read-only chat backed by Apple's on-device
/// Foundation Models. It can answer questions and explain concepts, but it has
/// no tools yet, so it cannot perform any action in App Store Connect.
@available(iOS 26.0, *)
@MainActor
final class AssistantViewModel: AssistantViewModelProtocol {

    @Published var uiState = AssistantUiState()

    private let session: LanguageModelSession

    init(storage: PersistentStorable? = nil) {
        let store: PersistentStorable = storage ?? SwiftDataStorable.shared
        let resolver = AppResolver(storage: store)
        let tools: [any Tool] = [
            ListAppsTool(resolver: resolver),
            ListReviewsTool(resolver: resolver, storage: store)
        ]

        session = LanguageModelSession(tools: tools) {
            """
            You are the StackConnect assistant, embedded in an iOS app that manages \
            Apple App Store Connect accounts and apps.

            You can inspect the user's data with the available tools:
            - Use `list_apps` to see the user's apps with their current App Store \
            status and latest version.
            - Use `list_reviews` to read the most recent customer reviews for a \
            specific app.

            Always call the appropriate tool when the user asks about their apps or \
            reviews instead of guessing. The data comes from what is currently \
            synced on the device, so it may be slightly out of date.

            You are in read-only mode: you can read and explain, but you cannot \
            perform any action that changes data in App Store Connect. If the user \
            asks you to release a version, reply to a review, or modify anything, \
            briefly explain that those actions are not available yet and that only \
            reading is supported for now.

            Be concise. Reply in the same language the user writes in.
            """
        }
    }

    /// Warms up the on-device model so the first response is faster and any
    /// availability problem (e.g. assets still downloading) surfaces early.
    func prewarm() {
        session.prewarm()
    }

    func sendCurrentInput() async {
        let prompt = uiState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !uiState.isResponding else { return }

        uiState.messages.append(AssistantMessage(role: .user, text: prompt))
        uiState.inputText = ""
        uiState.errorMessage = nil

        // The model can become unusable after the screen opened (for example
        // the assets are still downloading). Re-check before attempting to
        // generate, so we show a clear message instead of failing mid-request.
        if let unavailable = unavailableMessage() {
            uiState.errorMessage = unavailable
            return
        }

        uiState.isResponding = true

        do {
            let response = try await session.respond(to: prompt)
            uiState.messages.append(AssistantMessage(role: .assistant, text: response.content))
        } catch {
            uiState.errorMessage = Self.friendlyMessage(for: error)
            Log.print.error("[Assistant] Failed to generate response: \(error.localizedDescription)")
        }

        uiState.isResponding = false
    }

    // MARK: - Availability & errors

    /// A user-facing message when the model is not currently usable, or `nil`
    /// when it is available.
    private func unavailableMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return AssistantUnavailableView.message(for: reason)
        }
    }

    /// Translates a Foundation Models failure into a clear, actionable message
    /// instead of surfacing a raw `GenerationError` to the user.
    private static func friendlyMessage(for error: Error) -> String {
        if error is LanguageModelSession.GenerationError {
            return String(localized: "The on-device model isn’t available right now. Make sure Apple Intelligence is turned on and has finished downloading, then try again.")
        }
        return String(localized: "Something went wrong while generating a response. Please try again.")
    }

    func clearConversation() {
        uiState.messages.removeAll()
        uiState.errorMessage = nil
    }
}

#endif
