import FirebaseRemoteConfig
import Foundation

/// Remote flag values frozen at launch: a plain dictionary, so readers never
/// touch Firebase and the value can't change mid-session.
struct RemoteFeatureValueSnapshot: RemoteFeatureValueProviding, Equatable {
    let values: [String: Bool]

    func boolValue(forKey key: String) -> Bool? {
        values[key]
    }
}

/// Wires the remote feature flags (`FeatureFlag.remoteConfigKey`) to Firebase
/// Remote Config, once, at app start.
///
/// Read once per launch: the values ACTIVATED by the previous launch are
/// frozen into `FeatureFlags.launchRemoteValues` before any screen exists, so
/// Google Play surfaces (and any other remote flag) never change under the
/// user mid-session. Then a fetch + activate runs in the background; what it
/// brings applies on the NEXT launch.
///
/// Remote Config is configuration, not tracking: it runs whatever the
/// analytics opt-out says and never turns Analytics collection on (that stays
/// `AnalyticsService`'s job). Without Firebase (no `GoogleService-Info.plist`,
/// unit-test host, fake data mode) nothing is installed and every remote flag
/// keeps its compiled-in default (OFF).
enum RemoteFeatureFlagsBootstrap {

    /// 0 in Debug (iterate on the console freely), 1 hour in Release.
    static var minimumFetchInterval: TimeInterval {
        #if DEBUG
        return 0
        #else
        return 3600
        #endif
    }

    /// - Parameter firebaseConfigured: whether `FirebaseApp.configure()` ran
    ///   (`AnalyticsBootstrap.didConfigureFirebase`).
    @MainActor
    static func install(firebaseConfigured: Bool) {
        guard firebaseConfigured else {
            Log.print.info("[FeatureFlags] Firebase not configured: remote flags use their defaults")
            return
        }
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = minimumFetchInterval
        remoteConfig.configSettings = settings

        let snapshot = snapshot(of: remoteConfig)
        FeatureFlags.launchRemoteValues = snapshot
        Log.print.info("[FeatureFlags] Remote flags frozen for this launch: \(snapshot.values.count) value(s)")

        remoteConfig.fetchAndActivate { status, error in
            if let error {
                Log.print.error("[FeatureFlags] Remote Config fetch failed (defaults kept): \(error.localizedDescription)")
            } else {
                Log.print.info("[FeatureFlags] Remote Config fetched (status \(status.rawValue)); applies on the next launch")
            }
        }
    }

    /// The activated remote value of every flag with a `remoteConfigKey`. A
    /// parameter the activated config doesn't hold (default / static source)
    /// is left out, so the flag falls back to its default.
    private static func snapshot(of remoteConfig: RemoteConfig) -> RemoteFeatureValueSnapshot {
        var values: [String: Bool] = [:]
        for flag in FeatureFlag.allCases {
            guard let key = flag.remoteConfigKey else { continue }
            let value = remoteConfig.configValue(forKey: key)
            guard value.source == .remote else { continue }
            values[key] = value.boolValue
        }
        return RemoteFeatureValueSnapshot(values: values)
    }
}
