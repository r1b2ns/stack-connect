import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Foundation

/// How Firebase is used by this launch. Decided once, by
/// `AnalyticsBootstrap.firebaseMode(...)`, a pure function.
enum AnalyticsFirebaseMode: Equatable, Sendable {
    /// `FirebaseApp.configure()` is not called: no config file, a unit-test
    /// host or the fake data mode. Remote Config is unavailable too.
    case notConfigured
    /// Firebase is configured (Remote Config needs it) but nothing is sent:
    /// no Analytics / Crashlytics provider, and their collection is forced off.
    /// The default of DEBUG builds, so they never pollute the product's numbers.
    case configuredWithoutCollection
    /// Firebase is configured and the Analytics + Crashlytics providers are
    /// used (still behind the user's opt-out). Release builds, or a DEBUG
    /// launch with `-StackAnalyticsSendToFirebase YES`.
    case configuredWithCollection
}

/// Decides which analytics providers this build ships with.
///
/// Firebase is optional: `GoogleService-Info.plist` is git-ignored, so open
/// source checkouts and CI build without it. When the file is absent (or the app
/// is hosting unit tests, or runs on fake data) only the log provider is used —
/// so neither Analytics nor Crashlytics is ever set up there.
///
/// **DEBUG builds never send to Firebase by default.** Firebase is still
/// configured (Remote Config needs it), but only `LogAnalyticsProvider` is used,
/// and Analytics + Crashlytics collection are explicitly switched off (both SDKs
/// persist the last value set through their API, so a previous opted-in run
/// would otherwise keep collecting). To verify events in Firebase DebugView,
/// launch a DEBUG build with:
///
///     -StackAnalyticsSendToFirebase YES -FIRDebugEnabled
///
/// (or the environment variable `STACK_ANALYTICS_SEND_TO_FIREBASE=1`; the
/// launch argument wins). `-FIRDebugEnabled` is Firebase's own switch that
/// routes the events to DebugView. The opt-in is ignored in Release builds,
/// in unit-test hosts and in the fake data mode.
enum AnalyticsBootstrap {

    static let firebaseConfigResource = "GoogleService-Info"

    /// DEBUG-only opt-in to send analytics / crash data to Firebase anyway.
    static let sendToFirebaseArgumentKey = "StackAnalyticsSendToFirebase"
    static let sendToFirebaseEnvironmentKey = "STACK_ANALYTICS_SEND_TO_FIREBASE"

    /// `true` once `FirebaseApp.configure()` ran (read by
    /// `RemoteFeatureFlagsBootstrap`, which needs a configured Firebase app).
    nonisolated(unsafe) private(set) static var didConfigureFirebase = false

    /// Whether this is a DEBUG build.
    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Configures Firebase when possible and returns the providers to use.
    /// Called once, by `AnalyticsService.shared`.
    @MainActor
    static func makeDefaultProviders(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> [any AnalyticsProvider] {
        let mode = firebaseMode(bundle: bundle, processInfo: processInfo, isDebug: isDebugBuild)
        var providers: [any AnalyticsProvider] = []

        switch mode {
        case .notConfigured:
            Log.print.info("[Analytics] Mode: log only. Firebase not configured (no \(firebaseConfigResource).plist, unit-test host or fake data)")
        case .configuredWithoutCollection:
            configureFirebase()
            disableFirebaseCollection()
            Log.print.info("[Analytics] Mode: log only (DEBUG). Firebase configured for Remote Config; Analytics and Crashlytics collection off. Launch with -\(sendToFirebaseArgumentKey) YES to send to Firebase")
        case .configuredWithCollection:
            configureFirebase()
            providers.append(contentsOf: firebaseProviders())
            Log.print.info("[Analytics] Mode: Firebase (Analytics, Crashlytics)\(isDebugBuild ? " — DEBUG opt-in via -\(sendToFirebaseArgumentKey)" : "")")
        }

        #if DEBUG
        providers.append(LogAnalyticsProvider())
        #else
        if providers.isEmpty {
            providers.append(LogAnalyticsProvider())
        }
        #endif
        return providers
    }

    /// What a configured Firebase contributes: Analytics and Crashlytics, both
    /// behind `AnalyticsService`'s opt-out gate. Only called after
    /// `FirebaseApp.configure()`.
    static func firebaseProviders() -> [any AnalyticsProvider] {
        [FirebaseAnalyticsProvider(), CrashlyticsProvider()]
    }

    /// Firebase is configured only when its config file is bundled, and never
    /// while the app is the host of a unit-test run (tests must not send events)
    /// or runs on fake data.
    static func shouldUseFirebase(bundle: Bundle, processInfo: ProcessInfo) -> Bool {
        firebaseMode(bundle: bundle, processInfo: processInfo, isDebug: isDebugBuild) != .notConfigured
    }

    /// Reads the inputs of `firebaseMode(hasConfigFile:...)` from `bundle` and
    /// `processInfo`.
    static func firebaseMode(bundle: Bundle, processInfo: ProcessInfo, isDebug: Bool) -> AnalyticsFirebaseMode {
        let arguments = processInfo.arguments
        let environment = processInfo.environment
        #if DEBUG
        let isFakeData = FakeDataMode(arguments: arguments, environment: environment).isEnabled
        #else
        let isFakeData = false
        #endif
        return firebaseMode(
            hasConfigFile: bundle.path(forResource: firebaseConfigResource, ofType: "plist") != nil,
            isUnitTestHost: environment["XCTestConfigurationFilePath"] != nil,
            isFakeData: isFakeData,
            isDebug: isDebug,
            sendToFirebaseRequested: isSendToFirebaseRequested(arguments: arguments, environment: environment)
        )
    }

    /// The decision itself, pure.
    static func firebaseMode(
        hasConfigFile: Bool,
        isUnitTestHost: Bool,
        isFakeData: Bool,
        isDebug: Bool,
        sendToFirebaseRequested: Bool
    ) -> AnalyticsFirebaseMode {
        guard hasConfigFile, !isUnitTestHost else { return .notConfigured }
        guard isDebug else { return .configuredWithCollection }
        // Demo sessions on fake data must not reach the product's analytics.
        guard !isFakeData else { return .notConfigured }
        return sendToFirebaseRequested ? .configuredWithCollection : .configuredWithoutCollection
    }

    /// `-StackAnalyticsSendToFirebase YES|NO` (last occurrence wins) or, when the
    /// argument is absent, `STACK_ANALYTICS_SEND_TO_FIREBASE=1|0`.
    /// `YES` / `true` / `1` (case-insensitive) mean on; anything else is off.
    static func isSendToFirebaseRequested(arguments: [String], environment: [String: String]) -> Bool {
        var fromArguments: Bool?
        for (index, argument) in arguments.enumerated() where argument == "-\(sendToFirebaseArgumentKey)" {
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { continue }
            fromArguments = truthy(arguments[valueIndex])
        }
        return fromArguments ?? truthy(environment[sendToFirebaseEnvironmentKey]) ?? false
    }

    // MARK: - Private

    private static func truthy(_ raw: String?) -> Bool? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        switch raw {
        case "yes", "true", "1": return true
        case "no", "false", "0": return false
        default: return nil
        }
    }

    private static func configureFirebase() {
        // Not guarded with `FirebaseApp.app() == nil`: that getter logs
        // I-COR000003 when no app exists yet. This runs once, from
        // `AnalyticsService.shared`'s initialiser.
        FirebaseApp.configure()
        didConfigureFirebase = true
    }

    /// Forces both SDKs off for this launch. Info.plist already says
    /// `FIREBASE_ANALYTICS_COLLECTION_ENABLED = NO` and
    /// `FirebaseCrashlyticsCollectionEnabled = NO`, but both SDKs persist the
    /// value last set through their API, which overrides Info.plist: a DEBUG
    /// install that once ran with collection on (an older build, or the opt-in)
    /// would keep collecting. Crash reports stored by such a launch are deleted
    /// so they are never uploaded later.
    private static func disableFirebaseCollection() {
        Analytics.setAnalyticsCollectionEnabled(false)
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCrashlyticsCollectionEnabled(false)
        crashlytics.deleteUnsentReports()
    }
}
