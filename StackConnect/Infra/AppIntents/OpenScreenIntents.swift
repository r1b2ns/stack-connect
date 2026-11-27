import AppIntents

// MARK: - Opener

/// Hands an App Intent's screen to the SwiftUI app through the same path as
/// widget taps and `stackconnect://` URLs: `DeepLinkRouter.shared` sets
/// `pending`, which the root on screen (tab bar or split view) routes with
/// `HomeDeepLinkHandler`. On a cold launch `pending` waits until the root
/// subscribes, so the link is never lost.
///
/// Tracked as `app_opened_from` with `source=shortcut`.
@MainActor
enum ShortcutDeepLinkOpener {
    static func open(_ link: DeepLink, router: DeepLinkRouter = .shared) {
        router.open(link.url, source: .shortcut)
    }
}

// MARK: - Intents

/// Opens the ratings and reviews of every app (`stackconnect://reviews`).
struct OpenReviewsIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Open Reviews",
        comment: "App Shortcut (Siri, Spotlight, Shortcuts app): title of the action that opens the reviews of every app."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "Opens the latest ratings and reviews of your apps.",
        comment: "App Shortcut: description of the Open Reviews action."
    ))
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutDeepLinkOpener.open(.reviews)
        return .result()
    }
}

/// Opens TestFlight (`stackconnect://testflight`): the app's TestFlight when
/// there is a single app, else the list to pick one from.
struct OpenTestFlightIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Open TestFlight",
        comment: "App Shortcut (Siri, Spotlight, Shortcuts app): title of the action that opens TestFlight builds and testers of the user's apps."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "Opens the TestFlight builds and testers of your apps.",
        comment: "App Shortcut: description of the Open TestFlight action."
    ))
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutDeepLinkOpener.open(.testFlight)
        return .result()
    }
}

/// Opens Firebase Remote Config (`stackconnect://remote-config`).
struct OpenRemoteConfigIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Open Remote Config",
        comment: "App Shortcut (Siri, Spotlight, Shortcuts app): title of the action that opens Firebase Remote Config."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "Opens the Remote Config parameters of your Firebase projects.",
        comment: "App Shortcut: description of the Open Remote Config action."
    ))
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutDeepLinkOpener.open(.remoteConfig)
        return .result()
    }
}

/// Opens Settings › Privacy › Audit (`stackconnect://network-audit`; the Home
/// while the `networkAudit` flag is OFF).
struct OpenNetworkAuditIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "Open Network Audit",
        comment: "App Shortcut (Siri, Spotlight, Shortcuts app): title of the action that opens the on-device log of the app's network requests."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "Opens the on-device record of every network request the app made.",
        comment: "App Shortcut: description of the Open Network Audit action."
    ))
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutDeepLinkOpener.open(.networkAudit)
        return .result()
    }
}

// MARK: - Provider

/// The app's App Shortcuts: offered in Spotlight, Siri and the Shortcuts app
/// with no setup. Phrases live in `AppShortcuts.xcstrings` (Apple requires
/// that catalog for them); titles and descriptions in `Localizable.xcstrings`.
/// Every phrase names the app (`\(.applicationName)`).
struct StackConnectShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenReviewsIntent(),
            phrases: [
                "Open reviews in \(.applicationName)",
                "Show my app reviews in \(.applicationName)",
                "\(.applicationName) reviews"
            ],
            shortTitle: LocalizedStringResource("Reviews", comment: "App Shortcut tile: opens the reviews of every app."),
            systemImageName: "star.bubble"
        )
        AppShortcut(
            intent: OpenTestFlightIntent(),
            phrases: [
                "Open TestFlight in \(.applicationName)",
                "Show TestFlight builds in \(.applicationName)",
                "\(.applicationName) TestFlight"
            ],
            shortTitle: LocalizedStringResource("TestFlight", comment: "App Shortcut tile: opens TestFlight."),
            systemImageName: "airplane"
        )
        AppShortcut(
            intent: OpenRemoteConfigIntent(),
            phrases: [
                "Open Remote Config in \(.applicationName)",
                "\(.applicationName) Remote Config"
            ],
            shortTitle: LocalizedStringResource("Remote Config", comment: "App Shortcut tile: opens Firebase Remote Config."),
            systemImageName: "slider.horizontal.3"
        )
        AppShortcut(
            intent: OpenNetworkAuditIntent(),
            phrases: [
                "Open the network audit in \(.applicationName)",
                "\(.applicationName) network audit"
            ],
            shortTitle: LocalizedStringResource("Network Audit", comment: "App Shortcut tile: opens the on-device network audit."),
            systemImageName: "network.badge.shield.half.filled"
        )
    }
}
