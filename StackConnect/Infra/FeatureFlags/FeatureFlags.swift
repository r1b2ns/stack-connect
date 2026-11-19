import Foundation

/// Lightweight, reversible feature-flag registry for the app.
///
/// This is the first flag-based gate in the project, introduced to support the
/// gradual ("strangler-fig") migration of App Store Connect access to the shared
/// Rust core. Flags are read from `UserDefaults` so they can be toggled at runtime
/// (e.g. from a debug menu or a launch argument) without a rebuild, and they all
/// default to a SAFE value — OFF — so behaviour is unchanged unless explicitly
/// opted in.
///
/// Each case's `rawValue` is the `UserDefaults` key, namespaced under
/// `featureFlag.` to avoid collisions with other stored values.
enum FeatureFlag: String, CaseIterable {

    /// Debug-only tracer: when ON, the Rust core logs every App Store Connect HTTP
    /// call it makes as a runnable cURL command (with pretty-printed JSON
    /// request/response) straight to the Xcode console. Intended purely for
    /// diagnosing the Rust-core ASC integration during development; it has no
    /// behavioural effect on the app and zero overhead when OFF. Toggle at launch
    /// via the launch argument `-featureFlag.useRustCoreDebugLogging YES`.
    /// Default: OFF.
    case useRustCoreDebugLogging = "featureFlag.useRustCoreDebugLogging"

    /// Gates every Google Play release write entry point (plan R6): the release
    /// detail's bottom bar and editable metadata, the swipe actions on release
    /// rows, the staged rollout sheet, the review checklist and the New Release
    /// / Promote sheet ("+" on the app detail and on a track). Read-only release
    /// status and detail are not gated. A wrong tap changes production for real
    /// users, so writes stay OFF until validated against a real account.
    /// Default: OFF; ON while the DEBUG fake data mode runs (in memory only,
    /// see `FeatureFlags.sessionDefaults`). Toggle at launch with
    /// `-featureFlag.googlePlayReleaseWrites YES`.
    case googlePlayReleaseWrites = "featureFlag.googlePlayReleaseWrites"

    /// Gates "Sign in with Google" in Add Account for Google Play and Firebase
    /// (plan `google-sign-in.md` G9): the primary sign-in button and the
    /// picker of the Play apps / Firebase projects found. When OFF, Add
    /// Account shows only the service-account JSON form, as before. Accounts
    /// already added with Google keep working whatever the flag says.
    /// Default: ON in Debug builds, OFF in Release until the sign-in is
    /// verified on device. Toggle at launch with
    /// `-featureFlag.googleSignIn YES` / `NO`.
    case googleSignIn = "featureFlag.googleSignIn"

    /// Gates "Sign in with Apple ID" in Add Account for App Store Connect
    /// (plan `apple-id-sign-in.md` D6): the option next to the API key form
    /// and its three screens (Apple ID and password, two-factor code, team
    /// picker). When OFF, Add Account shows only the API key form, as before.
    /// Accounts already added with an Apple ID keep working whatever the flag
    /// says (the remote kill switch for them is Phase 4).
    /// Default: ON in Debug builds, OFF in Release until the review strategy
    /// is settled (plan Q4). Toggle at launch with
    /// `-featureFlag.appleIdSignIn YES` / `NO`.
    case appleIdSignIn = "featureFlag.appleIdSignIn"

    /// The compiled-in default used when no value is stored in `UserDefaults`.
    /// New flags ship OFF by default — the safe, fully-reversible value.
    var defaultValue: Bool {
        switch self {
        case .useRustCoreDebugLogging, .googlePlayReleaseWrites:
            return false
        case .googleSignIn, .appleIdSignIn:
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
    }
}

/// Resolves feature-flag values. Inject a custom `UserDefaults` in tests to
/// exercise both flag states without touching the shared store.
///
/// `@unchecked Sendable`: the only stored property is a `UserDefaults`, which is
/// documented as thread-safe, so this struct is safe to share across actors.
struct FeatureFlags: @unchecked Sendable {

    private let defaults: UserDefaults

    static let shared = FeatureFlags()

    /// Defaults for this launch only, applied between a stored value and the
    /// compiled-in default. Never persisted, so nothing leaks into a later
    /// launch. Set once at startup, before any screen exists — the DEBUG fake
    /// data mode turns `googlePlayReleaseWrites` ON this way.
    nonisolated(unsafe) static var sessionDefaults: [FeatureFlag: Bool] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns the current value of `flag`, falling back to its compiled-in
    /// default when nothing is stored.
    func isEnabled(_ flag: FeatureFlag) -> Bool {
        if defaults.object(forKey: flag.rawValue) == nil {
            return Self.sessionDefaults[flag] ?? flag.defaultValue
        }
        return defaults.bool(forKey: flag.rawValue)
    }

    /// Overrides `flag` at runtime (e.g. from a debug menu). Persists to the
    /// backing `UserDefaults`.
    func setEnabled(_ enabled: Bool, for flag: FeatureFlag) {
        defaults.set(enabled, forKey: flag.rawValue)
    }
}
