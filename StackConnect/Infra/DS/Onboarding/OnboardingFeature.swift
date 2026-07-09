import Foundation

/// Identifies a feature that has its own one-time onboarding.
///
/// Each case maps to a distinct persistence key (see ``OnboardingPresenter``) so
/// features are tracked independently — seeing one never affects another. Add a
/// new case here and a matching entry in ``OnboardingCatalog`` to introduce a
/// new onboarding.
enum OnboardingFeature: String, CaseIterable {
    case submissions
    case analytics
}
