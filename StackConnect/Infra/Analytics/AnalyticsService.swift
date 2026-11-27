import Foundation
import StackProtocols

/// Records handled errors as crash-reporter non-fatals. Split from
/// `AnalyticsTracking` (interface segregation): only the few places that still
/// hold a real `Error` need it.
@MainActor
protocol NonFatalErrorRecording: AnyObject {
    /// Records `error` when analytics is enabled and `category` is worth it
    /// (`AnalyticsErrorCategory.isReportableAsNonFatal`); dropped otherwise.
    func recordNonFatal(_ error: Error, category: AnalyticsErrorCategory)
}

/// What a component that tracks events *and* records non-fatals depends on.
typealias AnalyticsReporting = AnalyticsTracking & NonFatalErrorRecording

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
/// - User properties go through the same gate: while disabled they are only
///   remembered in memory (never handed to a provider) and pushed on opt-in,
///   so a re-enabled user is segmented correctly without waiting for the next
///   account change or launch.
///
/// The gate is read from `AppSettings` on every call, so there is no cached
/// state that can drift from what the Settings screen shows.
///
/// No user or device identifier is generated or attached.
///
/// Launch-time screen views: a `screen_view` tracked while the app is not
/// active yet (a root view's `onAppear` runs during scene connection, before
/// Firebase started the session, and GA4 then records it with screen name
/// "(not set)") is held in a `PendingScreenViewQueue` and sent, in order, once
/// `appActivity` reports the app active. Any later `screen_view` waits behind
/// held ones so the order is kept. Other events are never delayed. The gate is
/// checked again when the held events are sent, and opting out drops them.
@MainActor
final class AnalyticsService: AnalyticsTracking, AnalyticsUserPropertySetting, NonFatalErrorRecording {

    /// Built once, on first access, with the providers available in this build
    /// (Firebase only when `GoogleService-Info.plist` is bundled). `AppDelegate`
    /// touches it at launch, before anything is tracked.
    static let shared = AnalyticsService(
        providers: AnalyticsBootstrap.makeDefaultProviders(),
        appActivity: UIApplicationActivityMonitor()
    )

    private let providers: [any AnalyticsProvider]
    private let settings: AppSettings
    private let standardParameters: [String: AnalyticsValue]
    /// `nil`: the app is treated as always active (no screen view is held).
    private let appActivity: (any AppActivityMonitoring)?
    private var pendingScreenViews = PendingScreenViewQueue()

    /// The latest value of every user property set this session, sent or not.
    /// In memory only: it lets opt-in restore the segmentation.
    private var userProperties: [AnalyticsUserProperty: String] = [:]

    /// The flush/reset work started by the last opt-out. Exposed so tests can
    /// await it deterministically.
    private(set) var pendingFlush: Task<Void, Never>?

    init(
        providers: [any AnalyticsProvider] = [LogAnalyticsProvider()],
        settings: AppSettings = .shared,
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo,
        appActivity: (any AppActivityMonitoring)? = nil
    ) {
        self.providers = providers
        self.settings = settings
        self.standardParameters = Self.makeStandardParameters(bundle: bundle, processInfo: processInfo)
        self.appActivity = appActivity
        appActivity?.observeDidBecomeActive { [weak self] in
            self?.dispatchPendingScreenViews()
        }
    }

    var isEnabled: Bool {
        settings.isEnabled(.analyticsEnabled)
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return } // The single gate.
        if shouldHold(event) {
            pendingScreenViews.enqueue(event)
            Log.print.info("[Analytics] App not active yet: holding \(event.name) until it is")
            return
        }
        dispatch(event)
    }

    /// The held screen views, in order. Exposed for tests.
    var heldScreenViews: [AnalyticsEvent] { pendingScreenViews.events }

    /// Sends the screen views held while the app was not active, behind the
    /// opt-out gate (an opted-out user's held events are dropped). Called when
    /// `appActivity` reports the app became active.
    func dispatchPendingScreenViews() {
        guard !pendingScreenViews.isEmpty else { return }
        let held = pendingScreenViews.drain()
        guard isEnabled else { return } // The single gate, again.
        Log.print.info("[Analytics] App active: sending \(held.count) held screen view(s)")
        for event in held {
            dispatch(event)
        }
    }

    /// Sets user properties on every provider, but only while enabled (same
    /// gate as `track`). Unchanged values are not sent again.
    func setUserProperties(_ properties: [AnalyticsUserProperty: String]) {
        let changed = properties.filter { userProperties[$0.key] != $0.value }
        userProperties.merge(properties) { _, new in new }
        guard isEnabled, !changed.isEmpty else { return } // The single gate.
        dispatchUserProperties(changed)
    }

    /// Hands a scrubbed copy of `error` to every provider (Crashlytics), behind
    /// the same gate as `track`. Only `server` / `unknown` categories are
    /// recorded: the other ones are expected user-side failures.
    func recordNonFatal(_ error: Error, category: AnalyticsErrorCategory) {
        guard isEnabled, category.isReportableAsNonFatal else { return } // The single gate.
        let scrubbed = Self.scrubbed(error, category: category)
        for provider in providers {
            provider.recordNonFatal(scrubbed)
        }
    }

    /// `error`'s domain and code only, plus its category: the original
    /// `userInfo` (messages, URLs, response bodies…) never leaves the device.
    static func scrubbed(_ error: Error, category: AnalyticsErrorCategory) -> NSError {
        let nsError = error as NSError
        return NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: [AnalyticsParameterKey.errorCategory: category.rawValue]
        )
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
            // Before `analytics_enabled`, so that event is already segmented.
            dispatchUserProperties(userProperties)
            dispatch(.analyticsEnabled)
            Log.print.info("[Analytics] Sending enabled by the user")
        } else {
            // Held screen views of an opted-out user are never sent.
            pendingScreenViews.removeAll()
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

    /// A `screen_view` is held while the app is not active, and also while
    /// earlier ones are still held (so they keep their order).
    private func shouldHold(_ event: AnalyticsEvent) -> Bool {
        guard event.name == AnalyticsEventName.screenView, let appActivity else { return false }
        return !appActivity.isActive || !pendingScreenViews.isEmpty
    }

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

    /// Sends without checking the gate, in a stable (sorted) order. Only
    /// `setUserProperties` and `setEnabled` call it.
    private func dispatchUserProperties(_ properties: [AnalyticsUserProperty: String]) {
        for (property, value) in properties.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            for provider in providers {
                provider.setUserProperty(value, forName: property.rawValue)
            }
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
