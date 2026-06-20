import SwiftUI

/// Informational tip shown on App Store Connect resource list screens when Apple
/// blocks the account with a pending/updated Program License Agreement (403
/// PLA_NOT_ACCEPTED). Uses the app's standard `ContentUnavailableView` empty-state
/// convention so it reads as a friendly state, not a hard error.
struct PendingAgreementTip: View {

    /// App Store Connect's agreements console. Force-unwrap is safe: a fixed,
    /// compile-time-constant, well-formed URL that can never be nil.
    private static let agreementsURL = URL(string: "https://appstoreconnect.apple.com/agreements")!

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "Program License Agreement Required"),
                systemImage: "signature"
            )
        } description: {
            Text(String(localized: "Your team's Account Holder must accept the latest Apple Developer Program License Agreement in App Store Connect before these resources are available."))
        } actions: {
            Link(destination: Self.agreementsURL) {
                Text(String(localized: "Open App Store Connect"))
            }
            .buttonStyle(.borderedProminent)

            ShareLink(item: Self.agreementsURL) {
                Label(
                    String(localized: "Share Link"),
                    systemImage: "square.and.arrow.up"
                )
            }
            .buttonStyle(.bordered)
        }
    }
}
