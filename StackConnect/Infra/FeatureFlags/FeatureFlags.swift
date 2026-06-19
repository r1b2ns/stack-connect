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

    /// Routes ONLY the Apple connection's `validateCredentials()` and `fetchApps()`
    /// through the Rust core (UniFFI `Provider`) instead of the Swift App Store
    /// Connect SDK. All other Apple methods stay on the Swift SDK. Default: OFF.
    case useRustCoreForAppleApps = "featureFlag.useRustCoreForAppleApps"

    /// Debug-only tracer: when ON, the Rust core logs every App Store Connect HTTP
    /// call it makes as a runnable cURL command (with pretty-printed JSON
    /// request/response) straight to the Xcode console. Intended purely for
    /// diagnosing the Rust-core ASC integration during development; it has no
    /// behavioural effect on the app and zero overhead when OFF. Toggle at launch
    /// via the launch argument `-featureFlag.useRustCoreDebugLogging YES`.
    /// Default: OFF.
    case useRustCoreDebugLogging = "featureFlag.useRustCoreDebugLogging"

    /// Hides the App Store Connect "Analytics" option (the AppAnalytics /
    /// analytics-reports feature) from the app UI. That feature is still served by
    /// the legacy Swift App Store Connect SDK and has not yet been migrated to the
    /// shared Rust core, so this flag lets us hide it while the migration is
    /// pending. Ships OFF — Analytics stays VISIBLE by default; enabling the flag
    /// HIDES it. Default: OFF.
    case hideAnalytics = "featureFlag.hideAnalytics"

    /// The compiled-in default used when no value is stored in `UserDefaults`.
    /// New flags ship OFF by default — the safe, fully-reversible value.
    var defaultValue: Bool {
        switch self {
        case .useRustCoreForAppleApps:
            return false
        case .useRustCoreDebugLogging:
            return false
        case .hideAnalytics:
            return false
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns the current value of `flag`, falling back to its compiled-in
    /// default when nothing is stored.
    func isEnabled(_ flag: FeatureFlag) -> Bool {
        if defaults.object(forKey: flag.rawValue) == nil {
            return flag.defaultValue
        }
        return defaults.bool(forKey: flag.rawValue)
    }

    /// Overrides `flag` at runtime (e.g. from a debug menu). Persists to the
    /// backing `UserDefaults`.
    func setEnabled(_ enabled: Bool, for flag: FeatureFlag) {
        defaults.set(enabled, forKey: flag.rawValue)
    }
}
