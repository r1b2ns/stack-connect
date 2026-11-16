import Foundation

// MARK: - Protocol

/// The Google Play release write flow shared by the release detail, the app
/// detail (swipe actions, "+") and the tracks screen: every write is asked
/// for, confirmed (plan R4), committed, then announced with a toast. Screens
/// observe `uiState.revision` to reload their caches after a write.
@MainActor
protocol GooglePlayReleaseWriteViewModelProtocol: ObservableObject {
    var uiState: GooglePlayReleaseWriteUiState { get set }
    /// Whether write entry points of `kind` show at all (flag, scope, rules).
    func canPerform(_ kind: GooglePlayReleaseWriteAccess.Kind) -> Bool
    /// Starts `action` on `release` of `track` (a bar button, a swipe action).
    func start(_ action: GooglePlayReleaseAction, release: GooglePlayReleaseModel, track: String)
    /// Asks the user to confirm `write`. Nothing is sent until `confirm()`.
    func request(_ write: GooglePlayPendingWrite)
    /// Commits `write`, the one the user confirmed (an alert clears
    /// `pendingWrite` as it closes, before this runs). `true` on success.
    @discardableResult
    func confirm(_ write: GooglePlayPendingWrite) async -> Bool
    func cancelPendingWrite()
}

// MARK: - UiState

struct GooglePlayReleaseWriteUiState {
    /// Waiting for the user's confirmation.
    var pendingWrite: GooglePlayPendingWrite?
    var commitOptions = GooglePlayCommitOptions()
    var isWriting = false
    var toastMessage: ToastMessage?
    /// A failed write, already user-facing (alert).
    var errorMessage: String?
    /// Bumped after every successful write: screens reload their caches.
    var revision = 0
}

// MARK: - Implementation

@MainActor
final class GooglePlayReleaseWriteViewModel: GooglePlayReleaseWriteViewModelProtocol {

    @Published var uiState = GooglePlayReleaseWriteUiState()

    private let writer: GooglePlayReleaseWriter

    init(writer: GooglePlayReleaseWriter) {
        self.writer = writer
    }

    convenience init(app: GooglePlayAppItem, account: AccountModel) {
        self.init(writer: GooglePlayReleaseWriter(account: account, app: app))
    }

    func canPerform(_ kind: GooglePlayReleaseWriteAccess.Kind) -> Bool {
        writer.isAllowed(kind)
    }

    func start(_ action: GooglePlayReleaseAction, release: GooglePlayReleaseModel, track: String) {
        let codes = release.versionCodes
        let change: GooglePlayReleaseChange
        switch action {
        case .halt:
            change = .halt(versionCodes: codes)
        case .resume:
            change = .resume(versionCodes: codes)
        case .releaseToAll, .rollOut:
            change = .complete(versionCodes: codes)
        case .increaseRollout:
            change = .setRollout(versionCodes: codes, userFraction: Self.nextStep(after: release.userFraction ?? 0))
        case .promote:
            return
        }
        request(GooglePlayPendingWrite(track: track, change: change, releaseTitle: release.shortName))
    }

    func request(_ write: GooglePlayPendingWrite) {
        guard canPerform(.init(write.change)) else { return }
        uiState.errorMessage = nil
        uiState.pendingWrite = write
    }

    @discardableResult
    func confirm(_ write: GooglePlayPendingWrite) async -> Bool {
        guard !uiState.isWriting, canPerform(.init(write.change)) else { return false }
        uiState.isWriting = true
        defer { uiState.isWriting = false }
        do {
            try await writer.apply(write.change, track: write.track, options: uiState.commitOptions)
            uiState.pendingWrite = nil
            uiState.toastMessage = ToastMessage(write.successMessage)
            uiState.revision += 1
            return true
        } catch {
            Log.print.error("[GooglePlayReleaseWrite] Write failed: \(error.localizedDescription)")
            uiState.pendingWrite = nil
            uiState.errorMessage = (error as? GooglePlayReleaseWriteError)?.errorDescription
                ?? GooglePlayErrorTranslator.friendlyMessage(for: error, operation: .releaseChange)
            return false
        }
    }

    func cancelPendingWrite() {
        uiState.pendingWrite = nil
    }

    // MARK: - Rollout steps

    /// Steps Play Console suggests for a staged rollout.
    static let rolloutSteps: [Double] = [0.01, 0.05, 0.1, 0.2, 0.5, 0.99]

    /// The first step above `fraction`, or 99%.
    static func nextStep(after fraction: Double) -> Double {
        rolloutSteps.first { $0 > fraction + 0.0001 } ?? 0.99
    }
}
