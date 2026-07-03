import Foundation

/// User-facing application preferences, persisted in `UserDefaults`.
///
/// Distinct from `FeatureFlags` (developer/diagnostic gates): these are settings
/// the user toggles from the Settings screen. Each case's `rawValue` is the
/// `UserDefaults` key, namespaced under `appSetting.` to avoid collisions.
enum AppSetting: String, CaseIterable {

    /// When ON, submitting a version for App Store review first presents a
    /// read-only pre-submit checklist bottom sheet. Ships ON by default.
    case preReviewChecklistEnabled = "appSetting.preReviewChecklistEnabled"

    /// The compiled-in value used when nothing is stored in `UserDefaults`.
    var defaultValue: Bool {
        switch self {
        case .preReviewChecklistEnabled:
            return true
        }
    }
}

/// Reads/writes `AppSetting` values. Inject a custom `UserDefaults` in tests to
/// exercise both states without touching the shared store.
///
/// `@unchecked Sendable`: the only stored property is a `UserDefaults`, which is
/// documented as thread-safe, so this struct is safe to share across actors.
struct AppSettings: @unchecked Sendable {

    private let defaults: UserDefaults

    static let shared = AppSettings()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns the current value of `setting`, falling back to its compiled-in
    /// default when nothing is stored.
    func isEnabled(_ setting: AppSetting) -> Bool {
        if defaults.object(forKey: setting.rawValue) == nil {
            return setting.defaultValue
        }
        return defaults.bool(forKey: setting.rawValue)
    }

    /// Persists a new value for `setting` to the backing `UserDefaults`.
    func setEnabled(_ enabled: Bool, for setting: AppSetting) {
        defaults.set(enabled, forKey: setting.rawValue)
    }
}
