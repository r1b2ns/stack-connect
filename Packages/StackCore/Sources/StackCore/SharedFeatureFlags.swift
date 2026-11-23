import Foundation

/// Feature flag values the app mirrors into the App Group defaults for the
/// widget extension, which can't read the app's `FeatureFlags` (standard
/// defaults, launch arguments, Remote Config). The app writes the value
/// resolved for its launch; the extension only reads it.
public enum SharedFeatureFlags {

    /// Effective value of the app's `FeatureFlag.googlePlayAccounts`.
    public static let googlePlayAccountsKey = "sharedFeatureFlag.googlePlayAccounts"

    public static var appGroupDefaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }

    /// Whether the widgets may show Google Play (gallery preview, description,
    /// Android rows). `false` until the app wrote a value.
    public static func isGooglePlayAccountsEnabled(defaults: UserDefaults? = appGroupDefaults) -> Bool {
        defaults?.bool(forKey: googlePlayAccountsKey) ?? false
    }

    public static func setGooglePlayAccountsEnabled(_ enabled: Bool, defaults: UserDefaults? = appGroupDefaults) {
        defaults?.set(enabled, forKey: googlePlayAccountsKey)
    }
}
