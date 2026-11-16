import Foundation
import StackProtocols

/// The app's single analytics entry point. Owns the user opt-out gate
/// (`AppSetting.analyticsEnabled`) and fans events out to every provider.
///
/// Opt-out semantics:
/// - Default ON.
/// - Disabling while enabled dispatches `analytics_disabled` *first* (it is the
///   last event ever sent), then persists `false`, then flushes and resets the
///   providers. Every later `track` is dropped at the gate.
/// - Enabling while disabled persists `true`, turns provider collection back on,
///   then dispatches `analytics_enabled`.
/// - On launch, `applyCollectionSetting()` pushes the persisted value to every
///   provider so a vendor SDK never collects for an opted-out user.
/// - Setting the current value again sends nothing.
///
/// The gate is read from `AppSettings` on every call, so there is no cached
/// state that can drift from what the Settings screen shows.
///
/// No user or device identifier is generated or attached.
@MainActor
final class AnalyticsService: AnalyticsTracking {

    /// Built once, on first access, with the providers available in this build
    /// (Firebase only when `GoogleService-Info.plist` is bundled). `AppDelegate`
    /// touches it at launch, before anything is tracked.
    static let shared = AnalyticsService(providers: AnalyticsBootstrap.makeDefaultProviders())

    private let providers: [any AnalyticsProvider]
    private let settings: AppSettings
    private let standardParameters: [String: AnalyticsValue]

    /// The flush/reset work started by the last opt-out. Exposed so tests can
    /// await it deterministically.
    private(set) var pendingFlush: Task<Void, Never>?

    init(
        providers: [any AnalyticsProvider] = [LogAnalyticsProvider()],
        settings: AppSettings = .shared,
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.providers = providers
        self.settings = settings
        self.standardParameters = Self.makeStandardParameters(bundle: bundle, processInfo: processInfo)
    }

    var isEnabled: Bool {
        settings.isEnabled(.analyticsEnabled)
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return } // The single gate.
        dispatch(event)
    }

    /// Applies the persisted opt-out setting to every provider's own collection
    /// switch. Called once at launch.
    func applyCollectionSetting() {
        let enabled = isEnabled
        for provider in providers {
            provider.setCollectionEnabled(enabled)
        }
        Log.print.info("[Analytics] Collection \(enabled ? "enabled" : "disabled") at launch")
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return } // No-op: no duplicate events.

        if enabled {
            settings.setEnabled(true, for: .analyticsEnabled)
            for provider in providers {
                provider.setCollectionEnabled(true)
            }
            dispatch(.analyticsEnabled)
            Log.print.info("[Analytics] Sending enabled by the user")
        } else {
            // Order matters: the last event goes out while still enabled.
            dispatch(.analyticsDisabled)
            settings.setEnabled(false, for: .analyticsEnabled)
            Log.print.info("[Analytics] Sending disabled by the user")

            let providers = providers
            pendingFlush = Task {
                for provider in providers {
                    await provider.flush()
                    // Only now: `analytics_disabled` was already handed over.
                    provider.setCollectionEnabled(false)
                    provider.reset()
                }
            }
        }
    }

    // MARK: - Private

    /// Sends without checking the gate. Only `track` and `setEnabled` call it.
    private func dispatch(_ event: AnalyticsEvent) {
        // Standard parameters win over event ones so they cannot be spoofed.
        let enriched = AnalyticsEvent(
            name: event.name,
            parameters: event.parameters.merging(standardParameters) { _, standard in standard }
        )
        for provider in providers {
            provider.send(enriched)
        }
    }

    private static func makeStandardParameters(
        bundle: Bundle,
        processInfo: ProcessInfo
    ) -> [String: AnalyticsValue] {
        let info = bundle.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "unknown"
        let os = processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"

        return [
            AnalyticsParameterKey.appVersion: .string(appVersion),
            AnalyticsParameterKey.buildNumber: .string(buildNumber),
            AnalyticsParameterKey.platform: .string("ios"),
            AnalyticsParameterKey.osVersion: .string(osVersion)
        ]
    }
}
