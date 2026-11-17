#if DEBUG
import Foundation

/// Launch switches of the DEBUG-only fake data (demo accounts) mode.
///
/// - `-StackFakeData YES` (launch argument, read like the `UserDefaults`
///   argument domain) or `STACK_FAKE_DATA=1` (environment) runs the app entirely
///   on invented data: no network, no Keychain, no App Group store.
/// - `-StackFakeDataReset YES` or `STACK_FAKE_DATA_RESET=1` wipes the fake store
///   and seeds it again. It only has an effect together with the mode itself.
/// - `-StackFakeDataWidgets YES` or `STACK_FAKE_DATA_WIDGETS=1` also writes the
///   WidgetKit snapshot and the widget icons into the App Group, so the
///   home-screen widgets show the fake data (App Store screenshots). Without it
///   they stay on the real data. Only with the mode itself.
/// - `-StackFakePlayDeveloperId <value>` stores `<value>` verbatim as the fake
///   Google Play account's developer ID at launch (bypassing the input
///   normalizer), e.g. `abc` to see the Users tab's "invalid developer ID"
///   error and its report. Only with the mode itself.
/// - `-StackFakePlayQuota YES` makes every fake Play release-summary request
///   fail with the core's quota error (Http 429), to see the app list's quota
///   cooldown and its footer. Only with the mode itself.
///
/// The scheme "StackConnect Fake Data" (project.yml) pre-fills both arguments so
/// they can be toggled in Xcode's scheme editor. See `docs/FAKE_DATA.md`.
struct FakeDataMode: Equatable, Sendable {

    static let argumentKey = "StackFakeData"
    static let resetArgumentKey = "StackFakeDataReset"
    static let environmentKey = "STACK_FAKE_DATA"
    static let resetEnvironmentKey = "STACK_FAKE_DATA_RESET"
    static let widgetsArgumentKey = "StackFakeDataWidgets"
    static let widgetsEnvironmentKey = "STACK_FAKE_DATA_WIDGETS"
    static let playDeveloperIdArgumentKey = "StackFakePlayDeveloperId"
    static let playQuotaArgumentKey = "StackFakePlayQuota"

    /// Run on fake data.
    let isEnabled: Bool

    /// Wipe the fake store and seed it again (only meaningful when enabled).
    let shouldReset: Bool

    /// Feed the home-screen widgets (App Group) with the fake data (only
    /// meaningful when enabled).
    let feedsHomeScreenWidgets: Bool

    /// Developer ID forced on the fake Play account, verbatim (only meaningful
    /// when enabled).
    let playDeveloperId: String?

    /// Fake Play release-summary requests answer with a quota error (only
    /// meaningful when enabled).
    let simulatesPlayQuota: Bool

    /// The switches this process was launched with.
    static let current = FakeDataMode(
        arguments: ProcessInfo.processInfo.arguments,
        environment: ProcessInfo.processInfo.environment
    )

    init(
        isEnabled: Bool,
        shouldReset: Bool,
        feedsHomeScreenWidgets: Bool = false,
        playDeveloperId: String? = nil,
        simulatesPlayQuota: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.shouldReset = isEnabled && shouldReset
        self.feedsHomeScreenWidgets = isEnabled && feedsHomeScreenWidgets
        self.playDeveloperId = isEnabled ? playDeveloperId : nil
        self.simulatesPlayQuota = isEnabled && simulatesPlayQuota
    }

    /// Parses the launch arguments (`-Key value`, the `UserDefaults` argument
    /// domain syntax) and the environment. The argument wins over the environment
    /// when both are present.
    init(arguments: [String], environment: [String: String]) {
        let enabled = Self.flag(Self.argumentKey, in: arguments)
            ?? Self.truthy(environment[Self.environmentKey])
            ?? false
        let reset = Self.flag(Self.resetArgumentKey, in: arguments)
            ?? Self.truthy(environment[Self.resetEnvironmentKey])
            ?? false
        let widgets = Self.flag(Self.widgetsArgumentKey, in: arguments)
            ?? Self.truthy(environment[Self.widgetsEnvironmentKey])
            ?? false
        self.init(
            isEnabled: enabled,
            shouldReset: reset,
            feedsHomeScreenWidgets: widgets,
            playDeveloperId: Self.value(Self.playDeveloperIdArgumentKey, in: arguments),
            simulatesPlayQuota: Self.flag(Self.playQuotaArgumentKey, in: arguments) ?? false
        )
    }

    // MARK: - Parsing

    /// Value of `-key value` in `arguments`, or `nil` when the key is absent or
    /// has no value. The last occurrence wins, like the argument domain.
    private static func flag(_ key: String, in arguments: [String]) -> Bool? {
        var result: Bool?
        for (index, argument) in arguments.enumerated() where argument == "-\(key)" {
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { continue }
            result = truthy(arguments[valueIndex])
        }
        return result
    }

    /// Raw value of `-key value` in `arguments` (last occurrence wins).
    private static func value(_ key: String, in arguments: [String]) -> String? {
        var result: String?
        for (index, argument) in arguments.enumerated() where argument == "-\(key)" {
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { continue }
            result = arguments[valueIndex]
        }
        return result
    }

    /// `YES` / `true` / `1` → true, `NO` / `false` / `0` → false (case-insensitive),
    /// anything else (or `nil`) → `nil`.
    private static func truthy(_ raw: String?) -> Bool? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        switch raw {
        case "yes", "true", "1": return true
        case "no", "false", "0": return false
        default: return nil
        }
    }
}
#endif
