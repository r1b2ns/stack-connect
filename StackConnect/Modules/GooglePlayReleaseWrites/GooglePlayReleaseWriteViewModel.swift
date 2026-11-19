import Foundation
import StackProtocols

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
    /// Opens the New Release sheet, on `track` when given.
    func openNewRelease(track: String?)
    /// Bundles uploaded to Google Play (a temporary Play edit).
    func fetchBundles() async throws -> [GooglePlayBundleModel]
    /// Opens the Staged Rollout sheet on the release's current state.
    func openRollout(release: GooglePlayReleaseModel, track: String)
    /// Asks the user to confirm `write`. Nothing is sent until `confirm()`.
    func request(_ write: GooglePlayPendingWrite)
    /// Commits `write`, the one the user confirmed (an alert clears
    /// `pendingWrite` as it closes, before this runs). `true` on success.
    @discardableResult
    func confirm(_ write: GooglePlayPendingWrite) async -> Bool
    func cancelPendingWrite()
    /// Reads what the checklist compares against (cached tracks and store
    /// listing languages). Never a Play edit.
    func loadContext() async
    /// The Review Checklist of `write`.
    func checklist(for write: GooglePlayPendingWrite) -> GooglePlayReviewChecklist
    /// Account and app of a shared error report.
    var errorContext: ErrorReportContext { get }
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
    /// Staged Rollout sheet (prototype screen 4).
    var rolloutTarget: GooglePlayRolloutTarget?
    /// The sheet opened from "Increase Rollout": it starts on the next step.
    var rolloutIncreasing = false

    /// A failed write confirmed from the checklist: shown in the checklist
    /// (with Share Error), which stays open.
    var checklistError: String?
    /// Cached context of the checklist.
    var cachedTracks: [GooglePlayTrackModel] = []
    var listingLanguages: [String] = []

    /// A write sheet is open: confirmations show over it, not the screen.
    var isPresentingSheet: Bool {
        rolloutTarget != nil || newRelease != nil
    }

    /// New Release / Promote sheet (prototype screen 5).
    var newRelease: GooglePlayNewReleaseRequest?

    /// How the account calls Google Play: a service account or "Sign in with
    /// Google". Picks the edit warnings' and errors' wording.
    var authMethod: AccountAuthMethod = .keyFile
    /// The Google account's e-mail of a "Sign in with Google" account, named
    /// in its access copy; `nil` for a service account.
    var googleAccountEmail: String?

    /// Said in the Staged Rollout sheet's footer.
    var rolloutEditFooter: String {
        authMethod == .googleSignIn
            ? String(localized: "Saving opens a Play edit, updates the track and commits it. Any edit open with your Google account for the app elsewhere is cancelled.")
            : String(localized: "Saving opens a Play edit, updates the track and commits it. Any edit this service account has open elsewhere (for example a CI upload) is cancelled.")
    }

    /// Said in the Review Checklist's "Google Play Review" footer.
    var checklistEditFooter: String {
        authMethod == .googleSignIn
            ? String(localized: "Google validates the edit before committing. Publishing cancels any other edit open with your Google account for the app.")
            : String(localized: "Google validates the edit before committing. Publishing cancels any other edit this service account has open for the app, such as a CI upload in progress.")
    }

    /// The pending write when it is confirmed through the checklist.
    var checklistWrite: GooglePlayPendingWrite? {
        guard let pendingWrite, pendingWrite.usesChecklist else { return nil }
        return pendingWrite
    }
}

// MARK: - Implementation

@MainActor
final class GooglePlayReleaseWriteViewModel: GooglePlayReleaseWriteViewModelProtocol {

    @Published var uiState = GooglePlayReleaseWriteUiState()

    private let writer: GooglePlayReleaseWriter
    /// The screen hosting the flow (app detail, tracks, release detail):
    /// where commits and bundle listings are tracked.
    private let screen: AnalyticsScreen
    private let analytics: AnalyticsReporting

    init(
        writer: GooglePlayReleaseWriter,
        screen: AnalyticsScreen = .googlePlayAppDetail,
        analytics: AnalyticsReporting = AnalyticsService.shared
    ) {
        self.writer = writer
        self.screen = screen
        self.analytics = analytics
        uiState.authMethod = writer.account.authMethod
        uiState.googleAccountEmail = writer.googleAccountEmail
    }

    convenience init(app: GooglePlayAppItem, account: AccountModel, screen: AnalyticsScreen) {
        self.init(writer: GooglePlayReleaseWriter(account: account, app: app), screen: screen)
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
        case .releaseToAll:
            change = .complete(versionCodes: codes)
        case .rollOut where !GooglePlayReleaseActions.supportsStagedRollout(GooglePlayTrackKind(track: track)):
            change = .complete(versionCodes: codes)
        case .rollOut, .increaseRollout:
            guard canPerform(.edit) else { return }
            uiState.rolloutIncreasing = action == .increaseRollout
            uiState.rolloutTarget = GooglePlayRolloutTarget(track: track, release: release)
            return
        case .promote:
            guard canPerform(.add) else { return }
            uiState.newRelease = GooglePlayNewReleaseRequest(source: .promote(fromTrack: track, release: release))
            return
        }
        request(GooglePlayPendingWrite(track: track, change: change, releaseTitle: release.shortName, release: release))
    }

    func openNewRelease(track: String?) {
        guard canPerform(.add) else { return }
        uiState.newRelease = GooglePlayNewReleaseRequest(source: .bundle(track: track))
    }

    func fetchBundles() async throws -> [GooglePlayBundleModel] {
        do {
            let bundles = try await writer.fetchBundles()
            analytics.track(.action(.fetchBundles, on: .googlePlayBundlePicker, result: .success,
                                    parameters: [AnalyticsParameterKey.count: .int(bundles.count)]))
            return bundles
        } catch {
            let category = AnalyticsErrorCategory(connectionError: error)
            analytics.track(.action(.fetchBundles, on: .googlePlayBundlePicker, result: .failure, parameters: category.parameters))
            analytics.recordNonFatal(error, category: category)
            throw error
        }
    }

    func openRollout(release: GooglePlayReleaseModel, track: String) {
        guard canPerform(.edit) else { return }
        uiState.rolloutIncreasing = false
        uiState.rolloutTarget = GooglePlayRolloutTarget(track: track, release: release)
    }

    func request(_ write: GooglePlayPendingWrite) {
        guard canPerform(.init(write.change)) else { return }
        uiState.errorMessage = nil
        uiState.checklistError = nil
        uiState.pendingWrite = write
    }

    @discardableResult
    func confirm(_ write: GooglePlayPendingWrite) async -> Bool {
        guard !uiState.isWriting, canPerform(.init(write.change)) else { return false }
        uiState.isWriting = true
        uiState.checklistError = nil
        defer { uiState.isWriting = false }
        do {
            try await writer.apply(write.change, track: write.track, options: uiState.commitOptions)
            trackWrite(write, result: .success)
            uiState.pendingWrite = nil
            uiState.toastMessage = ToastMessage(write.successMessage)
            uiState.revision += 1
            return true
        } catch {
            Log.print.error("[GooglePlayReleaseWrite] Write failed: \(error.localizedDescription)")
            let category = AnalyticsErrorCategory(connectionError: error)
            trackWrite(write, result: .failure, parameters: category.parameters)
            analytics.recordNonFatal(error, category: category)
            let message = (error as? GooglePlayReleaseWriteError)?.errorDescription
                ?? GooglePlayErrorTranslator.friendlyMessage(for: error, operation: .releaseChange, authMethod: uiState.authMethod, accountEmail: uiState.googleAccountEmail)
            if write.usesChecklist {
                // The checklist stays open with the error (and Share Error).
                uiState.checklistError = message
            } else {
                uiState.pendingWrite = nil
                uiState.errorMessage = message
            }
            return false
        }
    }

    func cancelPendingWrite() {
        uiState.pendingWrite = nil
        uiState.checklistError = nil
    }

    func loadContext() async {
        let context = await writer.cachedContext()
        uiState.cachedTracks = context.tracks
        uiState.listingLanguages = context.listingLanguages
    }

    func checklist(for write: GooglePlayPendingWrite) -> GooglePlayReviewChecklist {
        let track = uiState.cachedTracks.first { $0.track == write.track }
        return GooglePlayReviewChecklist.make(
            write: write,
            listingLanguages: uiState.listingLanguages,
            liveVersionCode: GooglePlayReviewChecklist.liveVersionCode(on: track, excluding: write.change.versionCodes)
        )
    }

    /// `release_write` with the change's kind and track kind — never the
    /// release name, version codes or a custom track's name.
    private func trackWrite(
        _ write: GooglePlayPendingWrite,
        result: AnalyticsResult,
        parameters: [String: AnalyticsValue] = [:]
    ) {
        var merged = parameters
        merged[AnalyticsParameterKey.kind] = .string(AnalyticsReleaseWriteKind(write.change).rawValue)
        merged[AnalyticsParameterKey.track] = .string(AnalyticsTrackKind(track: write.track).rawValue)
        if write.usesChecklist {
            merged[AnalyticsParameterKey.sendForReview] = .bool(uiState.commitOptions.sendForReview)
        }
        // A checklist confirmation is tracked on the checklist screen.
        let screen = write.usesChecklist ? AnalyticsScreen.googlePlayReviewChecklist : self.screen
        analytics.track(.action(.releaseWrite, on: screen, result: result, parameters: merged))
    }

    var errorContext: ErrorReportContext {
        ErrorReportContext(screen: String(localized: "Review Checklist"), account: writer.account, app: writer.app)
    }
}
