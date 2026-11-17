import Foundation

/// Decides when to ask for an App Store review.
///
/// Rules:
/// - Launches are counted once per process (`registerLaunch()`), persisted in
///   `UserDefaults`.
/// - A review is requested only right after a successful foreground (`.full`)
///   sync — every account synced, no error at all.
/// - Only on launches 3, 6, 9, … (launch count >= 3 and a multiple of 3).
/// - At most once per launch.
///
/// The actual `requestReview()` call lives in the view layer
/// (`ReviewPromptModifier`), since `RequestReviewAction` comes from the SwiftUI
/// environment. StoreKit still applies its own yearly cap on top of this.
@MainActor
final class ReviewPromptService {

    /// `UserDefaults` key of the persisted launch counter.
    nonisolated static let launchCountKey = "reviewPrompt.launchCount"

    /// Every `launchInterval`-th launch is eligible (3, 6, 9, …).
    nonisolated static let launchInterval = 3

    static let shared = ReviewPromptService(isEnabled: ReviewPromptService.isEnabledForCurrentProcess)

    private let defaults: UserDefaults
    private let isEnabled: Bool
    /// Whether this process already counted its launch.
    private(set) var hasRegisteredLaunch = false
    private(set) var hasRequestedThisLaunch = false

    /// - Parameters:
    ///   - defaults: Backing store of the launch counter. Inject a suite in tests.
    ///   - isEnabled: `false` turns the prompt off entirely (unit-test host,
    ///     DEBUG fake data / demo sessions).
    init(defaults: UserDefaults = .standard, isEnabled: Bool = true) {
        self.defaults = defaults
        self.isEnabled = isEnabled
    }

    /// Launches counted so far, including the current one once registered.
    var launchCount: Int {
        defaults.integer(forKey: Self.launchCountKey)
    }

    /// Counts the current launch. Idempotent per instance, so calling it again
    /// (another scene, the app coming back to the foreground) is harmless.
    func registerLaunch() {
        guard isEnabled, !hasRegisteredLaunch else { return }
        hasRegisteredLaunch = true
        let count = launchCount + 1
        defaults.set(count, forKey: Self.launchCountKey)
        Log.print.info("[ReviewPrompt] Launch registered (#\(count))")
    }

    /// Whether a review should be requested now, after a sync that ended with
    /// `syncSucceeded`. Does not change any state: call
    /// `markRequestedThisLaunch()` once the request is actually made.
    func shouldRequestReview(syncSucceeded: Bool) -> Bool {
        guard isEnabled, hasRegisteredLaunch else { return false }
        return Self.shouldRequestReview(
            launchCount: launchCount,
            syncSucceeded: syncSucceeded,
            alreadyRequestedThisLaunch: hasRequestedThisLaunch
        )
    }

    /// Records that the review was requested, blocking any further request
    /// until the next launch.
    func markRequestedThisLaunch() {
        hasRequestedThisLaunch = true
        Log.print.info("[ReviewPrompt] Review requested on launch #\(self.launchCount)")
    }

    // MARK: - Pure rules

    /// The decision itself, free of any state.
    nonisolated static func shouldRequestReview(
        launchCount: Int,
        syncSucceeded: Bool,
        alreadyRequestedThisLaunch: Bool
    ) -> Bool {
        guard syncSucceeded, !alreadyRequestedThisLaunch else { return false }
        return launchCount >= launchInterval && launchCount.isMultiple(of: launchInterval)
    }

    /// Whether the `old` → `new` transition is the end of a successful
    /// foreground sync: a `.full` run that covered at least one account just
    /// finished with no run-level error and no failed account. Background
    /// (`.lightweight`) runs never count, nor does a run with no account (the
    /// user hasn't seen the app do anything yet).
    nonisolated static func isSuccessfulForegroundSyncCompletion(from old: SyncState, to new: SyncState) -> Bool {
        old.isSyncing
            && !new.isSyncing
            && new.lastRunMode == .full
            && new.lastRunAccountCount > 0
            && new.lastRunSucceeded
    }

    // MARK: - Environment

    /// Off while hosting unit tests and, in DEBUG, in fake data (demo /
    /// screenshot) sessions, so no review sheet shows over them.
    nonisolated static var isEnabledForCurrentProcess: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #if DEBUG
        if FakeDataMode.current.isEnabled { return false }
        #endif
        return true
    }
}
