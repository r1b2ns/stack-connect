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

    init() {
        session = LanguageModelSession {
            """
            You are the StackConnect assistant, embedded in an iOS app that manages \
            Apple App Store Connect accounts and apps.

            Help the user understand their apps, reviews, app versions and phased \
            releases, and answer general questions about App Store Connect.

            You are currently in read-only mode: you can explain and answer, but you \
            cannot perform any action that changes data in App Store Connect. If the \
            user asks you to release a version, reply to a review, or modify anything, \
            briefly explain that those actions are not available yet and that only \
            reading is supported for now.

            Be concise. Reply in the same language the user writes in.
            """
        }
    }

    func sendCurrentInput() async {
        let prompt = uiState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !uiState.isResponding else { return }

        uiState.messages.append(AssistantMessage(role: .user, text: prompt))
        uiState.inputText = ""
        uiState.errorMessage = nil
        uiState.isResponding = true

        do {
            let response = try await session.respond(to: prompt)
            uiState.messages.append(AssistantMessage(role: .assistant, text: response.content))
        } catch {
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[Assistant] Failed to generate response: \(error.localizedDescription)")
        }

        uiState.isResponding = false
    }

    func clearConversation() {
        uiState.messages.removeAll()
        uiState.errorMessage = nil
    }
}

#endif
