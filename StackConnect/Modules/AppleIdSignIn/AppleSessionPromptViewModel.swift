import Combine
import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol AppleSessionPromptViewModelProtocol: ObservableObject {
    var uiState: AppleSessionPromptUiState { get set }
    /// App Store Connect refused `appleId`'s session (`isNew`: first refusal
    /// since it last worked).
    func sessionDidExpire(appleId: String, isNew: Bool)
    /// "Sign In Again": opens the sign-in for that Apple ID.
    func signInAgain()
    /// "Not Now" (or a swipe down): hides the prompt for that Apple ID until
    /// the next launch. The button itself is tracked by the DS prompt.
    func notNow()
    /// The new sign-in finished: the session was replaced.
    func signInFinished()
}

// MARK: - UiState

struct AppleSessionPrompt: Identifiable, Equatable {
    let appleId: String
    var id: String { appleId }
}

struct AppleSessionPromptUiState: Equatable {
    /// The expired session to ask about, shown as a sheet over the app.
    var prompt: AppleSessionPrompt?
    /// The sheet shows the sign-in instead of the prompt.
    var isSigningIn = false
}

// MARK: - Implementation

/// The app-wide "sign in again" prompt for an expired Apple ID session (plan
/// `apple-id-sign-in.md` D5). Any App Store Connect call of a session account
/// can find the session expired; instead of every screen handling it, the
/// connection records it (`AppleSessionStatusStore`) and this prompt, at the
/// root of the app, offers the sign-in once per Apple ID per launch. The
/// screens themselves show the translated error
/// (`AppleAPIErrorTranslator.sessionExpiredMessage`).
///
/// An expiry the automatic sign-in handles (a saved password,
/// `AppleSessionAutoReauthenticating`) shows no prompt: it renews the session
/// on its own, or leaves a code to type from the Home banner. The prompt
/// shows only once that attempt falls back to the manual sign-in (wrong
/// password, any other failure), and closes if it succeeds meanwhile.
@MainActor
final class AppleSessionPromptViewModel: AppleSessionPromptViewModelProtocol {

    @Published var uiState = AppleSessionPromptUiState()

    private let analytics: AnalyticsTracking
    private let center: NotificationCenter?
    /// Apple IDs whose prompt was dismissed with "Not Now" this launch.
    private var snoozed = Set<String>()
    private var observer: NSObjectProtocol?
    private let autoReauth: (any AppleSessionAutoReauthenticating)?
    private var cancellables = Set<AnyCancellable>()

    init(
        analytics: AnalyticsTracking = AnalyticsService.shared,
        center: NotificationCenter? = .default,
        autoReauth: (any AppleSessionAutoReauthenticating)? = nil
    ) {
        self.analytics = analytics
        self.center = center
        self.autoReauth = autoReauth
        autoReauth?.events
            .sink { [weak self] event in self?.autoReauthEvent(event) }
            .store(in: &cancellables)
        guard let center else { return }
        observer = center.addObserver(forName: .appleSessionDidExpire, object: nil, queue: .main) { [weak self] note in
            guard let appleId = note.object as? String else { return }
            let isNew = note.userInfo?[AppleSessionStatusStore.isNewKey] as? Bool ?? false
            MainActor.assumeIsolated {
                self?.sessionDidExpire(appleId: appleId, isNew: isNew)
            }
        }
    }

    deinit {
        if let observer { center?.removeObserver(observer) }
    }

    func sessionDidExpire(appleId: String, isNew: Bool) {
        if isNew {
            analytics.track(.action(.appleSessionExpired, on: nil))
        }
        if autoReauth?.handlesExpiry(of: appleId) == true {
            Log.print.info("[AppleSession] The automatic sign-in handles the expiry: no prompt")
            return
        }
        showPrompt(appleId: appleId)
    }

    private func showPrompt(appleId: String) {
        guard uiState.prompt == nil, !snoozed.contains(appleId) else { return }
        uiState.prompt = AppleSessionPrompt(appleId: appleId)
        uiState.isSigningIn = false
    }

    /// The automatic sign-in ended: the manual prompt takes over after a
    /// failure, and a prompt left over closes after a success (unless the
    /// user is already signing in there).
    private func autoReauthEvent(_ event: AppleSessionAutoReauthEvent) {
        guard case let .finished(appleId, outcome) = event else { return }
        if outcome.fallsBackToManualSignIn {
            showPrompt(appleId: appleId)
        } else if outcome == .done, uiState.prompt?.appleId == appleId, !uiState.isSigningIn {
            uiState = AppleSessionPromptUiState()
        }
    }

    func signInAgain() {
        guard uiState.prompt != nil else { return }
        analytics.track(.buttonTap(.signInAgain, on: .appleSessionExpired))
        uiState.isSigningIn = true
    }

    func notNow() {
        guard let prompt = uiState.prompt else { return }
        snoozed.insert(prompt.appleId)
        uiState = AppleSessionPromptUiState()
    }

    func signInFinished() {
        if let prompt = uiState.prompt {
            snoozed.remove(prompt.appleId)
        }
        uiState = AppleSessionPromptUiState()
    }
}
