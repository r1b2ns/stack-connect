import StoreKit
import SwiftUI

/// Counts the launch the first time the scene becomes active and asks for an
/// App Store review after a successful foreground sync, following the rules of
/// `ReviewPromptService`.
///
/// The launch is counted on the first `.active` scene phase (not at process
/// start) so a cold launch by a background refresh task, which the user never
/// sees, does not count.
private struct ReviewPromptModifier: ViewModifier {

    @ObservedObject var syncService: SyncService
    let reviewPrompt: ReviewPromptService

    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    reviewPrompt.registerLaunch()
                }
            }
            .onChange(of: syncService.state) { old, new in
                handleSyncStateChange(from: old, to: new)
            }
    }

    private func handleSyncStateChange(from old: SyncState, to new: SyncState) {
        // Only the end of a run matters.
        guard old.isSyncing, !new.isSyncing else { return }
        // A sync finishing while the app isn't in front (background refresh)
        // must not prompt.
        guard scenePhase == .active else { return }

        let succeeded = ReviewPromptService.isSuccessfulForegroundSyncCompletion(from: old, to: new)
        guard reviewPrompt.shouldRequestReview(syncSucceeded: succeeded) else {
            Log.print.info("[ReviewPrompt] Not requesting (sync succeeded: \(succeeded), launch #\(reviewPrompt.launchCount), already requested: \(reviewPrompt.hasRequestedThisLaunch))")
            return
        }
        reviewPrompt.markRequestedThisLaunch()
        requestReview()
    }
}

extension View {
    /// Asks for an App Store review after a successful foreground sync on every
    /// third launch. Apply once, on the root view.
    @MainActor
    func reviewPromptOnSuccessfulSync(
        syncService: SyncService = .shared,
        reviewPrompt: ReviewPromptService = .shared
    ) -> some View {
        modifier(ReviewPromptModifier(syncService: syncService, reviewPrompt: reviewPrompt))
    }
}
