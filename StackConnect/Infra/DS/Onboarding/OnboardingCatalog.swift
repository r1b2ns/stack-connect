import Foundation

/// Single source of truth for onboarding content, keyed by ``OnboardingFeature``.
///
/// Mirrors the `ImportTutorial` style: all copy is localized here so views never
/// hardcode feature strings. Introducing a new onboarding means adding a case to
/// ``OnboardingFeature`` and a branch here.
enum OnboardingCatalog {

    static func content(for feature: OnboardingFeature) -> OnboardingContent {
        switch feature {
        case .submissions:
            return submissions
        case .analytics:
            return analytics
        }
    }

    // MARK: - Submissions

    private static var submissions: OnboardingContent {
        OnboardingContent(
            title: String(localized: "Review Submissions"),
            highlightedTitle: nil,
            features: [
                OnboardingContent.Feature(
                    icon: "paperplane.fill",
                    color: .blue,
                    title: String(localized: "Manage Submissions"),
                    description: String(localized: "Track your App Store review submissions and their status, all in one place.")
                ),
                OnboardingContent.Feature(
                    icon: "arrow.uturn.backward.circle.fill",
                    color: .orange,
                    title: String(localized: "Discard or Resubmit"),
                    description: String(localized: "Swipe to discard a stuck submission or submit one that's ready for review.")
                ),
                OnboardingContent.Feature(
                    icon: "gauge.with.dots.needle.33percent",
                    color: .green,
                    title: String(localized: "Concurrency Limits"),
                    description: String(localized: "See how many submissions are in review against Apple's concurrent limit.")
                )
            ],
            continueTitle: String(localized: "Continue")
        )
    }

    // MARK: - Analytics

    private static var analytics: OnboardingContent {
        OnboardingContent(
            title: String(localized: "Analytics Reports"),
            highlightedTitle: nil,
            features: [
                OnboardingContent.Feature(
                    icon: "chart.bar.xaxis",
                    color: .blue,
                    title: String(localized: "App Store Connect Reports"),
                    description: String(localized: "Browse analytics reports grouped by category, straight from App Store Connect.")
                ),
                OnboardingContent.Feature(
                    icon: "arrow.down.circle.fill",
                    color: .orange,
                    title: String(localized: "Download & Keep"),
                    description: String(localized: "Download report files and keep them saved on your device.")
                ),
                OnboardingContent.Feature(
                    icon: "wifi.slash",
                    color: .green,
                    title: String(localized: "Available Offline"),
                    description: String(localized: "Open your saved reports anytime, even without a connection.")
                )
            ],
            continueTitle: String(localized: "Continue")
        )
    }
}
