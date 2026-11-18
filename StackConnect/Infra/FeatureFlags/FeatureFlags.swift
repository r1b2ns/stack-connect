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

    /// Gates every Google Play surface of the app (App Review guideline
    /// 2.3.10): the Google Play option of the provider pickers, the Google Play
    /// card / sidebar section / Settings section, Google Play accounts and apps
    /// in every account list, the Android rows of the Home widgets, All Reviews
    /// and the WidgetKit snapshot, the "Google Play" reviews filter, Google
    /// Play deep links, background sync of Google Play accounts, Google Play
    /// files in account import and the fake data mode's Google Play account.
    /// When OFF, stored Google Play accounts are hidden, never deleted. The
    /// single policy is `FeatureFlags.isProviderAvailable(_:)` /
    /// `visibleAccounts(_:)`.
    ///
    /// Remote: resolved from Firebase Remote Config parameter
    /// `google_play_accounts_enabled` (see `remoteConfigKey`), read ONCE per
    /// launch — a newly fetched value applies on the next launch, so the UI
    /// never changes under the user mid-session. A stored value (e.g. the
    /// launch argument `-featureFlag.googlePlayAccounts YES`) wins over it.
    /// Default: OFF, including in the DEBUG fake data mode.
    case googlePlayAccounts = "featureFlag.googlePlayAccounts"

    /// Gates "Sign in with Google" in Add Account for Google Play and Firebase
    /// (plan `google-sign-in.md` G9): the primary sign-in button and the
    /// picker of the Play apps / Firebase projects found. When OFF, Add
    /// Account shows only the service-account JSON form, as before. Accounts
    /// already added with Google keep working whatever the flag says.
    /// Default: ON in Debug builds, OFF in Release until the sign-in is
    /// verified on device. Toggle at launch with
    /// `-featureFlag.googleSignIn YES` / `NO`.
    case googleSignIn = "featureFlag.googleSignIn"

    /// The compiled-in default used when no value is stored in `UserDefaults`.
    /// New flags ship OFF by default — the safe, fully-reversible value.
    var defaultValue: Bool {
        switch self {
        case .useRustCoreDebugLogging, .googlePlayReleaseWrites, .googlePlayAccounts:
            return false
        case .googleSignIn:
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
    }

    /// The Firebase Remote Config parameter (Bool) that drives this flag, or
    /// `nil` for a local-only flag.
    var remoteConfigKey: String? {
        switch self {
        case .googlePlayAccounts:
            return "google_play_accounts_enabled"
        case .useRustCoreDebugLogging, .googlePlayReleaseWrites, .googleSignIn:
            return nil
        }
    }
}

/// Remote values of the flags that have a `remoteConfigKey`. Returns `nil`
/// when the parameter is absent from the activated config (or the remote
/// source is unavailable), so the flag falls back to its default. Kept free of
/// Firebase types so `FeatureFlags` stays testable.
protocol RemoteFeatureValueProviding: Sendable {
    func boolValue(forKey key: String) -> Bool?
}

/// Resolves feature-flag values. Inject a custom `UserDefaults` in tests to
/// exercise both flag states without touching the shared store.
///
/// `@unchecked Sendable`: the only stored property is a `UserDefaults`, which is
/// documented as thread-safe, so this struct is safe to share across actors.
struct FeatureFlags: @unchecked Sendable {

    private let defaults: UserDefaults
    private let remoteValue: @Sendable (String) -> Bool?

    static let shared = FeatureFlags()

    /// The remote values frozen at launch (`RemoteFeatureFlagsBootstrap`), or
    /// `nil` when Firebase isn't configured (no `GoogleService-Info.plist`,
    /// unit-test host, fake data mode). Set once at startup, before any screen.
    nonisolated(unsafe) static var launchRemoteValues: (any RemoteFeatureValueProviding)?

    /// Defaults for this launch only, applied between a stored value and the
    /// compiled-in default. Never persisted, so nothing leaks into a later
    /// launch. Set once at startup, before any screen exists — the DEBUG fake
    /// data mode turns `googlePlayReleaseWrites` ON this way.
    nonisolated(unsafe) static var sessionDefaults: [FeatureFlag: Bool] = [:]

    /// - Parameter remoteValues: the remote source to use. When omitted, the
    ///   values frozen at launch (`launchRemoteValues`) are read.
    init(defaults: UserDefaults = .standard, remoteValues: (any RemoteFeatureValueProviding)? = nil) {
        self.defaults = defaults
        if let remoteValues {
            self.remoteValue = { remoteValues.boolValue(forKey: $0) }
        } else {
            self.remoteValue = { FeatureFlags.launchRemoteValues?.boolValue(forKey: $0) }
        }
    }

    /// Returns the current value of `flag`. Precedence: a value stored in
    /// `UserDefaults` (a launch argument such as `-featureFlag.X YES` lands
    /// here too) > the remote value activated at launch (flags with a
    /// `remoteConfigKey`) > the session default > the compiled-in default.
    func isEnabled(_ flag: FeatureFlag) -> Bool {
        if defaults.object(forKey: flag.rawValue) != nil {
            return defaults.bool(forKey: flag.rawValue)
        }
        if let key = flag.remoteConfigKey, let remote = remoteValue(key) {
            return remote
        }
        return Self.sessionDefaults[flag] ?? flag.defaultValue
    }

    /// Overrides `flag` at runtime (e.g. from a debug menu). Persists to the
    /// backing `UserDefaults`.
    func setEnabled(_ enabled: Bool, for flag: FeatureFlag) {
        defaults.set(enabled, forKey: flag.rawValue)
    }
}
