import Foundation

/// What a page of the connection guide is about, in the order shown.
enum ConnectionGuidePageKind: String, CaseIterable, Hashable, Sendable {
    /// The app talks straight to the service: no server or account of ours.
    case howItWorks
    /// Where the credentials are kept and where they go, per method.
    case credentials
    /// The code is public: links to the repository and the privacy policy.
    case openSource
    /// The ways to connect this provider (what the chooser offers next).
    case methods
}

/// One page of the connection guide.
struct ConnectionGuidePage: Identifiable, Hashable, Sendable {
    let kind: ConnectionGuidePageKind
    let systemImage: String
    let title: String
    let message: String
    /// The page's main card of facts.
    var items: [StackTrustItem] = []
    /// A second card: one entry per method available for the provider.
    var notes: [StackTrustItem] = []
    var links: [StackExternalLinkItem] = []
    var footnote: String?

    var id: ConnectionGuidePageKind { kind }
}

/// The connection guide's copy, built for one provider and the methods this
/// build offers for it (`AccountConnectionMethod.available(for:…)`).
///
/// App Review rules the copy follows (keep them when editing):
/// - It names only the provider being connected (its `displayName`) and
///   describes only that provider's available methods: never another
///   provider's name or credential types.
/// - Without the email and password method, nothing mentions passwords to
///   sign in or two-factor codes.
/// - Claims match `PRIVACY.md` and the App Privacy label: credentials stay on
///   this device and go only to the service connected; anonymous analytics
///   and crash reports exist (and never include credentials).
/// - At most `maximumPageCount` pages; skipping is the guide view's job.
enum ConnectionGuideContent {

    static let maximumPageCount = 4

    static func pages(for provider: ProviderType, methods: [AccountConnectionMethod]) -> [ConnectionGuidePage] {
        // Defensive: only this provider's methods, whatever the caller passes.
        let ownMethods = AccountConnectionMethod.available(for: provider, appleIdSignIn: true, googleSignIn: true)
        let methods = methods.filter(ownMethods.contains)

        var pages = [
            howItWorksPage(provider),
            credentialsPage(provider, methods: methods),
            openSourcePage()
        ]
        if !methods.isEmpty {
            pages.append(methodsPage(provider, methods: methods))
        }
        return pages
    }

    // MARK: - Pages

    private static func howItWorksPage(_ provider: ProviderType) -> ConnectionGuidePage {
        ConnectionGuidePage(
            kind: .howItWorks,
            systemImage: "arrow.left.arrow.right",
            title: String(localized: "A Direct Connection",
                          comment: "Connection guide, page 1 title: the app talks directly to the service being connected."),
            message: String(localized: "StackConnect connects this device straight to \(provider.displayName), using only the access you give it.",
                            comment: "Connection guide, page 1. The placeholder is the service being connected, e.g. App Store Connect."),
            items: [
                StackTrustItem(systemImage: "server.rack",
                               text: String(localized: "No StackConnect server in between",
                                            comment: "Connection guide, page 1 fact.")),
                StackTrustItem(systemImage: "person.crop.circle.badge.xmark",
                               text: String(localized: "No StackConnect account to create",
                                            comment: "Connection guide, page 1 fact.")),
                StackTrustItem(systemImage: "internaldrive",
                               text: String(localized: "Data you load is kept on this device, for offline use",
                                            comment: "Connection guide, page 1 fact: data loaded from the service is cached on the device."))
            ]
        )
    }

    private static func credentialsPage(_ provider: ProviderType, methods: [AccountConnectionMethod]) -> ConnectionGuidePage {
        ConnectionGuidePage(
            kind: .credentials,
            systemImage: "lock.shield.fill",
            title: String(localized: "Your Credentials Stay on This Device",
                          comment: "Connection guide, page 2 title."),
            message: String(localized: "What you use to connect to \(provider.displayName) is kept on this device and used only for that.",
                            comment: "Connection guide, page 2. The placeholder is the service being connected, e.g. Firebase."),
            items: [
                StackTrustItem(systemImage: "lock.fill",
                               text: String(localized: "Stored in the iOS Keychain, on this device only",
                                            comment: "Connection guide, page 2 fact about credentials.")),
                StackTrustItem(systemImage: "icloud.slash",
                               text: String(localized: "Not synced through iCloud or restored to other devices",
                                            comment: "Connection guide, page 2 fact about credentials.")),
                StackTrustItem(systemImage: "hand.raised.fill",
                               text: String(localized: "Never sent to the developer",
                                            comment: "Connection guide, page 2 fact about credentials.")),
                StackTrustItem(systemImage: "eye.slash",
                               text: neverInLogs)
            ],
            notes: methods.map { credentialNote(for: $0, provider: provider) },
            footnote: String(localized: "StackConnect sends anonymous usage analytics and crash reports. They never include credentials, and you can turn them off in Settings.",
                             comment: "Connection guide, page 2 footnote. Must stay consistent with the App Privacy label (analytics and crash data are collected).")
        )
    }

    private static func openSourcePage() -> ConnectionGuidePage {
        ConnectionGuidePage(
            kind: .openSource,
            systemImage: "chevron.left.forwardslash.chevron.right",
            title: String(localized: "Open Source",
                          comment: "Connection guide, page 3 title: the app's code is public."),
            message: String(localized: "StackConnect's code is public on GitHub. Anyone can read it and check how credentials are stored and used.",
                            comment: "Connection guide, page 3."),
            links: [
                .sourceCode,
                .privacyPolicy
            ]
        )
    }

    private static func methodsPage(_ provider: ProviderType, methods: [AccountConnectionMethod]) -> ConnectionGuidePage {
        let hasChoice = methods.count > 1
        return ConnectionGuidePage(
            kind: .methods,
            systemImage: hasChoice ? "arrow.triangle.branch" : methods[0].systemImage,
            title: hasChoice
                ? String(localized: "Choose How to Connect",
                         comment: "Connection guide, last page title when the service can be connected in more than one way.")
                : String(localized: "How You'll Connect",
                         comment: "Connection guide, last page title when the service can be connected in one way only."),
            message: hasChoice
                ? String(localized: "There's more than one way to connect to \(provider.displayName). Pick one on the next screen.",
                         comment: "Connection guide, last page. The placeholder is the service being connected, e.g. App Store Connect.")
                : String(localized: "Here's what you'll use to connect to \(provider.displayName).",
                         comment: "Connection guide, last page with a single way to connect. The placeholder is the service being connected."),
            items: methods.map {
                StackTrustItem(systemImage: $0.systemImage, title: $0.title, text: $0.summary(for: provider))
            }
        )
    }

    // MARK: - Per-method notes

    /// Where `method`'s credential is kept and where it goes. Only ever built
    /// for a method available on `provider`'s own path.
    static func credentialNote(for method: AccountConnectionMethod, provider: ProviderType) -> StackTrustItem {
        switch method {
        case .apiKey:
            return StackTrustItem(
                systemImage: method.systemImage,
                title: String(localized: "API Key"),
                text: String(localized: "The .p8 private key only signs short-lived tokens on this device; the key itself is never sent. It leaves this device only if you export the account yourself, in a file encrypted with a password you choose.",
                             comment: "Connection guide, page 2: how an App Store Connect API key is handled.")
            )
        case .appleIdSignIn:
            return StackTrustItem(
                systemImage: method.systemImage,
                title: String(localized: "Email and Password",
                              comment: "Connection guide, page 2: heading of the note about the App Store Connect email and password method."),
                text: String(localized: "Your password is sent only to Apple, to sign you in. It's saved on this device only if you turn on \"Save password on this device\". Two-factor codes are never saved.",
                             comment: "Connection guide, page 2: how the email and password method handles the password. \"Save password on this device\" is the toggle of the password screen.")
            )
        case .googleSignIn:
            return StackTrustItem(
                systemImage: method.systemImage,
                title: String(localized: "Google Account"),
                text: String(localized: "You type your Google password on Google's own page, never in StackConnect. Only the access Google grants is kept, in this device's Keychain.",
                             comment: "Connection guide, page 2: how Sign in with Google is handled.")
            )
        case .serviceAccount:
            return StackTrustItem(
                systemImage: method.systemImage,
                title: String(localized: "Service Account Key"),
                text: provider.supportsExport
                    ? String(localized: "The service account's private key only signs short-lived tokens on this device; the key itself is never sent. It leaves this device only if you export the account yourself, in a file encrypted with a password you choose.",
                             comment: "Connection guide, page 2: how a service account key is handled, for a service whose accounts can be exported.")
                    : String(localized: "The service account's private key only signs short-lived tokens on this device; the key itself is never sent.",
                             comment: "Connection guide, page 2: how a service account key is handled, for a service whose accounts can't be exported.")
            )
        }
    }

    // MARK: - Shared copy

    /// Same key and comment as step 4 of "How Your Password Is Used".
    private static var neverInLogs: String {
        String(localized: "Never in logs, analytics or crash reports",
               comment: "Credentials (connection guide) or the Apple ID password (How Your Password Is Used) never appear in logs, analytics or crash reports.")
    }
}
