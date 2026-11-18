import Foundation
import StackProtocols

/// The single place that reacts to the end of a foreground sync with the
/// prompts tied to it, in a fixed order:
/// 1. the App Store review request (`ReviewPromptService`),
/// 2. then the Home "support the project" card (`TipJarPromptService`), which
///    is told whether a review was just requested so the two never stack in
///    the same launch, regardless of view-modifier ordering.
///
/// The view layer (`ReviewPromptModifier`) only forwards sync state changes
/// and performs the actual `requestReview()` when told to.
@MainActor
final class PostSyncPrompts {

    static let shared = PostSyncPrompts(reviewPrompt: .shared, tipJarPrompt: .shared)

    let reviewPrompt: ReviewPromptService
    private let tipJarPrompt: TipJarPromptService
    private let analytics: AnalyticsTracking

    init(
        reviewPrompt: ReviewPromptService,
        tipJarPrompt: TipJarPromptService,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.reviewPrompt = reviewPrompt
        self.tipJarPrompt = tipJarPrompt
        self.analytics = analytics
    }

    /// Handles the `old` → `new` sync state transition.
    ///
    /// - Returns: `true` when the caller must request an App Store review now
    ///   (it is already recorded as requested for this launch).
    func handleSyncStateChange(from old: SyncState, to new: SyncState, isSceneActive: Bool) -> Bool {
        // Only the end of a run matters.
        guard old.isSyncing, !new.isSyncing else { return false }
        // A sync finishing while the app isn't in front (background refresh)
        // must not prompt.
        guard isSceneActive else { return false }

        let succeeded = ReviewPromptService.isSuccessfulForegroundSyncCompletion(from: old, to: new)

        let shouldRequestReview = reviewPrompt.shouldRequestReview(syncSucceeded: succeeded)
        if shouldRequestReview {
            reviewPrompt.markRequestedThisLaunch()
            // StoreKit decides whether the prompt is actually displayed.
            analytics.track(.action(.reviewPromptRequested, on: .home))
        } else {
            Log.print.info("[ReviewPrompt] Not requesting (sync succeeded: \(succeeded), launch #\(self.reviewPrompt.launchCount), already requested: \(self.reviewPrompt.hasRequestedThisLaunch))")
        }

        // Decided after the review on purpose: a review requested now (or
        // earlier in this launch) blocks the card.
        tipJarPrompt.evaluateAfterSync(
            syncSucceeded: succeeded && reviewPrompt.hasRegisteredLaunch,
            launchCount: reviewPrompt.launchCount,
            reviewRequestedThisLaunch: reviewPrompt.hasRequestedThisLaunch
        )

        return shouldRequestReview
    }
}
