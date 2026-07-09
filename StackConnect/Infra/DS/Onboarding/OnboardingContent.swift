import SwiftUI

// MARK: - Model

/// Declarative content for a single ``OnboardingView`` presentation.
///
/// The onboarding is content-driven: a screen picks the ``OnboardingContent``
/// for its feature from ``OnboardingCatalog`` and hands it to ``OnboardingView``,
/// which knows how to render any content without feature-specific branching.
struct OnboardingContent {

    /// Primary headline (e.g. `"Welcome to"`). Shown in `.largeTitle`/`.bold`.
    let title: String

    /// Optional accented second line, drawn in `Color.accentColor`.
    /// When `nil`, the title stays a single line.
    let highlightedTitle: String?

    /// The highlighted feature rows shown to the user.
    let features: [Feature]

    /// Label for the dismissal button (e.g. `"Continue"`).
    let continueTitle: String

    struct Feature: Identifiable {
        /// SF Symbol name.
        let icon: String
        /// Tint applied to the icon.
        let color: Color
        let title: String
        let description: String

        var id: String { icon + title }
    }
}
