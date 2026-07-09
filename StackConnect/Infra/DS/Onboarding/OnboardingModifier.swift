import SwiftUI

/// Attaches a one-time, feature-scoped onboarding sheet to any screen.
///
/// The first time the host view appears and the feature hasn't been seen, it
/// presents ``OnboardingView`` as a non-dismissable sheet (matching the app's
/// welcome flow). Tapping continue marks the feature seen so it never shows
/// again. Reuse it with the ``SwiftUI/View/featureOnboarding(_:presenter:)``
/// one-liner.
private struct OnboardingModifier: ViewModifier {

    let feature: OnboardingFeature
    let presenter: OnboardingPresenter

    @State private var isPresented = false
    @State private var didEvaluate = false

    func body(content: Content) -> some View {
        content
            .onAppear(perform: evaluate)
            .sheet(isPresented: $isPresented) {
                OnboardingView(content: OnboardingCatalog.content(for: feature)) {
                    presenter.markSeen(feature)
                    isPresented = false
                }
                .interactiveDismissDisabled(true)
            }
    }

    /// Decides once, on the first appearance, whether to present. Guarded so
    /// re-appearances (tab switches, navigation pops) never re-trigger it.
    private func evaluate() {
        guard !didEvaluate else { return }
        didEvaluate = true

        guard presenter.shouldPresent(feature) else { return }

        Log.print.info("[Onboarding] presenting \(feature.rawValue)")
        isPresented = true
    }
}

extension View {

    /// Presents ``feature``'s onboarding once, the first time this view appears.
    /// - Parameters:
    ///   - feature: The feature to introduce.
    ///   - presenter: Persistence gate. Injectable for tests/previews.
    func featureOnboarding(
        _ feature: OnboardingFeature,
        presenter: OnboardingPresenter = OnboardingPresenter()
    ) -> some View {
        modifier(OnboardingModifier(feature: feature, presenter: presenter))
    }
}
