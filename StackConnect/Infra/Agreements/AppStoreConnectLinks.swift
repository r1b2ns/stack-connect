import Foundation

/// Fixed App Store Connect web URLs shared across screens, so the same link is
/// never spelled out (and drifts) in more than one place.
enum AppStoreConnectLinks {

    /// App Store Connect's agreements console, where the team's Account Holder
    /// reviews and accepts pending agreements. Force-unwrap is safe: a fixed,
    /// compile-time-constant, well-formed URL that can never be nil.
    static let agreements = URL(string: "https://appstoreconnect.apple.com/agreements/")!
}
