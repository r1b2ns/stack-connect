import Foundation
@testable import StackConnect

extension FeatureFlags {

    /// Flags backed by a fresh, private `UserDefaults` suite (never the shared
    /// store), with `googlePlayAccounts` set as asked and no remote value.
    static func testing(googlePlayAccounts: Bool) -> FeatureFlags {
        let suite = "FeatureFlagsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defaults.set(googlePlayAccounts, forKey: FeatureFlag.googlePlayAccounts.rawValue)
        return FeatureFlags(defaults: defaults, remoteValues: StubRemoteFeatureValues())
    }

    /// Google Play visible: what the tests written before the flag assume.
    static var googlePlayOn: FeatureFlags { testing(googlePlayAccounts: true) }
    static var googlePlayOff: FeatureFlags { testing(googlePlayAccounts: false) }

    /// Flags on a fresh, private suite with `networkAudit` set as asked.
    static func testing(networkAudit: Bool) -> FeatureFlags {
        let suite = "FeatureFlagsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defaults.set(networkAudit, forKey: FeatureFlag.networkAudit.rawValue)
        return FeatureFlags(defaults: defaults, remoteValues: StubRemoteFeatureValues())
    }
}

/// Remote Config stand-in: the given values, nothing else.
struct StubRemoteFeatureValues: RemoteFeatureValueProviding {
    var values: [String: Bool] = [:]

    func boolValue(forKey key: String) -> Bool? {
        values[key]
    }
}
