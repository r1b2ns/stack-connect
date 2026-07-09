import Foundation

/// Decides whether a feature's one-time onboarding should be presented.
///
/// Each ``OnboardingFeature`` is tracked independently under its own
/// `"hasSeenOnboarding.<feature>"` key, so acknowledging one onboarding never
/// suppresses another. Mirrors ``ReleaseNotesPresenter``: a small value type
/// over an injectable `UserDefaults`, trivial to unit test.
struct OnboardingPresenter {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Persistence key for a given feature (e.g. `"hasSeenOnboarding.submissions"`).
    static func key(for feature: OnboardingFeature) -> String {
        "hasSeenOnboarding.\(feature.rawValue)"
    }

    /// `true` when the feature's onboarding has not been seen yet.
    func shouldPresent(_ feature: OnboardingFeature) -> Bool {
        !hasSeen(feature)
    }

    /// `true` once ``markSeen(_:)`` has recorded this feature.
    func hasSeen(_ feature: OnboardingFeature) -> Bool {
        defaults.bool(forKey: Self.key(for: feature))
    }

    /// Records the feature's onboarding as seen so it won't show again.
    func markSeen(_ feature: OnboardingFeature) {
        defaults.set(true, forKey: Self.key(for: feature))
    }
}
