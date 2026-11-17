import StoreKit
import SwiftUI

/// Counts the launch the first time the scene becomes active and, after each
/// foreground sync, runs `PostSyncPrompts`: the App Store review request
/// (rules in `ReviewPromptService`), then the Home tip card
/// (`TipJarPromptService`).
///
/// The launch is counted on the first `.active` scene phase (not at process
/// start) so a cold launch by a background refresh task, which the user never
/// sees, does not count.
private struct ReviewPromptModifier: ViewModifier {

    @ObservedObject var syncService: SyncService
    let prompts: PostSyncPrompts

    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    prompts.reviewPrompt.registerLaunch()
                }
            }
            .onChange(of: syncService.state) { old, new in
                let shouldRequestReview = prompts.handleSyncStateChange(
                    from: old,
                    to: new,
                    isSceneActive: scenePhase == .active
                )
                if shouldRequestReview {
                    requestReview()
                }
            }
    }
}

extension View {
    /// Asks for an App Store review after a successful foreground sync on every
    /// third launch, then decides the Home tip card. Apply once, on the root view.
    @MainActor
    func reviewPromptOnSuccessfulSync(
        syncService: SyncService = .shared,
        prompts: PostSyncPrompts = .shared
    ) -> some View {
        modifier(ReviewPromptModifier(syncService: syncService, prompts: prompts))
    }
}
