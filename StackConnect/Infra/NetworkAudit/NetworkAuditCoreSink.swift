import Foundation
import StackCoreRust
import StackProtocols

// MARK: - Annotations

/// What the Rust core knows about an exchange beyond the HTTP itself, carried
/// next to the `NetworkAuditExchange` into the recorder.
struct NetworkAuditAnnotations: Sendable, Equatable {

    /// The core's credential hint.
    enum Credential: Sendable, Equatable {
        /// No hint: the recorder decodes `Authorization` itself.
        case none
        /// The request carried no credential.
        case unauthenticated
        case known(NetworkAuditCredentialInfo.Kind, expiresAt: Date?)
    }

    /// How much of a body the core handed over.
    enum BodyState: Sendable, Equatable {
        case captured
        case empty
        case truncated
        case binary
        case notCaptured
        case unavailable
    }

    var category: NetworkAuditCategory?
    var credential: Credential = .none
    var requestBodyState: BodyState?
    var responseBodyState: BodyState?
    /// Raw core operation (`reviews.fetch_customer_reviews`).
    var operation: String?
    /// The parent operation, readable.
    var parentOrigin: String?
    var attempt: Int?
    /// The core's account id (issuer ID, Apple ID, service account e-mail,
    /// Google login ID), resolved to the account name by the recorder.
    var coreAccountId: String?
    /// Body fields masked for good on top of the usual secrets (SRP values
    /// and the two-factor code of an Apple ID sign-in).
    var extraSecretFields: Set<String> = []
}

extension NetworkAuditCredentialInfo.Kind {
    /// The kinds a cURL export may ever carry (still subject to expiry and Face ID).
    var isShortLivedKind: Bool {
        self == .appStoreConnectJWT || self == .googleAccessToken
    }
}

// MARK: - Core sink

/// Where mapped core entries go: `NetworkAuditRecorder`.
protocol NetworkAuditCoreRecording: Sendable {
    func recordCore(_ exchange: NetworkAuditExchange, annotations: NetworkAuditAnnotations)
}

extension NetworkAuditRecorder: NetworkAuditCoreRecording {}

/// The Rust core's audit hook (`StackCoreRust.NetworkAuditSink`), adapted to
/// the app's recorder.
///
/// The core calls both methods synchronously on its worker thread, once per
/// exchange: `record(entry:)` only maps the entry (no masking, no I/O) and
/// hands it to the recorder, which masks, seals and writes on a background
/// task. Entries are RAW — live bearer tokens, OAuth token responses, SRP
/// values, the two-factor code — and never leave this type unmasked except
/// into the recorder.
final class NetworkAuditCoreSink: StackCoreRust.NetworkAuditSink, @unchecked Sendable {

    private let recorder: NetworkAuditCoreRecording
    private let settings: NetworkAuditSettingsProviding

    init(recorder: NetworkAuditCoreRecording, settings: NetworkAuditSettingsProviding) {
        self.recorder = recorder
        self.settings = settings
    }

    func record(entry: NetworkAuditEntry) {
        guard let (exchange, annotations) = NetworkAuditCoreEntryMapper.map(entry) else {
            Log.print.warning("[NetworkAudit] Dropped a core entry with an unreadable URL")
            return
        }
        recorder.recordCore(exchange, annotations: annotations)
    }

    /// Follows "Full bodies": without it the core reports sizes only.
    func captureBodies() -> Bool {
        settings.recordsFullBodies
    }
}

// MARK: - Factory

/// The audit sink every core entry point gets: the shared adapter while the
/// `networkAudit` flag is ON and the recorder is installed, `nil` otherwise
/// (the core then records nothing at all).
enum NetworkAuditCoreSinkFactory {

    nonisolated(unsafe) private static var cached: NetworkAuditCoreSink?
    private static let lock = NSLock()

    static func make(
        featureFlags: FeatureFlags = .shared,
        recorder: NetworkAuditRecorder? = NetworkAuditRecorder.shared
    ) -> StackCoreRust.NetworkAuditSink? {
        guard featureFlags.isEnabled(.networkAudit), let recorder else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.isBound(to: recorder) {
            return cached
        }
        let sink = NetworkAuditCoreSink(recorder: recorder, settings: recorder.settings)
        cached = sink
        return sink
    }
}

private extension NetworkAuditCoreSink {
    func isBound(to recorder: NetworkAuditRecorder) -> Bool {
        (self.recorder as AnyObject) === recorder
    }
}

// MARK: - Mapper

/// Pure mapping of a core entry. Tested on its own.
enum NetworkAuditCoreEntryMapper {

    static func map(_ entry: NetworkAuditEntry) -> (NetworkAuditExchange, NetworkAuditAnnotations)? {
        guard let url = URL(string: entry.url)
            ?? entry.url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:)) else {
            return nil
        }

        let isAppleSignIn = entry.operation.hasPrefix("apple_id.") || url.host?.lowercased() == "idmsa.apple.com"
        let annotations = NetworkAuditAnnotations(
            category: category(of: entry.provider),
            credential: credential(entry.credentialKind, expiresAtMs: entry.tokenExpiresAtMs),
            requestBodyState: bodyState(entry.requestBodyState),
            responseBodyState: bodyState(entry.responseBodyState),
            operation: entry.operation,
            parentOrigin: entry.parentOperation.map(NetworkAuditOperationCatalog.title),
            attempt: Int(entry.attempt),
            coreAccountId: entry.accountId,
            extraSecretFields: isAppleSignIn ? NetworkAuditSecretMasker.appleSignInSecretFields : []
        )

        let exchange = NetworkAuditExchange(
            source: .rustCore,
            startedAt: Date(timeIntervalSince1970: Double(entry.startedAtMs) / 1000),
            duration: Double(entry.durationMs) / 1000,
            method: entry.method,
            url: url,
            requestHeaders: entry.requestHeaders.map(field),
            requestBody: entry.requestBody.map { Data($0.utf8) },
            requestBodyLength: Int64(clamping: entry.requestSizeBytes),
            statusCode: entry.responseStatus.map(Int.init),
            responseHeaders: entry.responseHeaders.map(field),
            responseBody: entry.responseBody.map { Data($0.utf8) },
            responseBodyLength: Int64(clamping: entry.responseSizeBytes),
            httpVersion: entry.httpVersion.map(httpVersion),
            errorDescription: entry.error,
            origin: NetworkAuditOperationCatalog.title(entry.operation),
            purpose: NetworkAuditOperationCatalog.purpose(entry.operation)
        )
        return (exchange, annotations)
    }

    static func category(of provider: NetworkAuditProvider) -> NetworkAuditCategory? {
        switch provider {
        case .appleApi, .appleWebSession: return .apple
        case .googlePlay, .googleOauth, .firebase: return .google
        case .other: return nil
        }
    }

    static func credential(_ kind: NetworkAuditCredentialKind, expiresAtMs: Int64?) -> NetworkAuditAnnotations.Credential {
        let expiry = expiresAtMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        switch kind {
        case .ascJwt: return .known(.appStoreConnectJWT, expiresAt: expiry)
        case .googleAccessToken: return .known(.googleAccessToken, expiresAt: expiry)
        case .appleSessionCookie: return .known(.appleSessionCookie, expiresAt: nil)
        case .oauthAssertion: return .known(.oauthAssertion, expiresAt: nil)
        case .unauthenticated: return .unauthenticated
        }
    }

    static func bodyState(_ state: NetworkAuditBodyState) -> NetworkAuditAnnotations.BodyState {
        switch state {
        case .captured: return .captured
        case .empty: return .empty
        case .truncated: return .truncated
        case .binary: return .binary
        case .notCaptured: return .notCaptured
        case .unavailable: return .unavailable
        }
    }

    /// `HTTP/2.0` → `HTTP/2`, like the URLSession events.
    static func httpVersion(_ value: String) -> String {
        switch value.uppercased() {
        case "HTTP/2.0": return "HTTP/2"
        case "HTTP/3.0": return "HTTP/3"
        default: return value.uppercased()
        }
    }

    private static func field(_ header: StackCoreRust.NetworkAuditHeader) -> NetworkAuditExchange.HeaderField {
        NetworkAuditExchange.HeaderField(name: header.name, value: header.value)
    }
}

// MARK: - Operation catalog

/// Readable names for the core's operations (`docs/NETWORK_AUDIT.md` of the
/// core). Unknown operations are prettified, never hidden:
/// `reviews.fetch_customer_reviews` → "Ratings and Reviews · fetch customer reviews".
enum NetworkAuditOperationCatalog {

    static func title(_ operation: String) -> String {
        if let known = knownTitle(operation) { return known }
        let parts = operation.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return prettified(operation) }
        let area = areaTitle(parts[0]) ?? prettified(parts[0]).capitalized
        return "\(area) · \(prettified(parts[1]))"
    }

    static func purpose(_ operation: String) -> String? {
        switch operation {
        case "provider.validate":
            return String(localized: "Check that the account's credentials work.", comment: "Network audit purpose: the core's provider.validate.")
        case "provider.fetch_apps", "sync.sync_apps":
            return String(localized: "Load the account's app list.", comment: "Network audit purpose: the core's app list fetch / sync.")
        case "apple_id.start":
            return String(localized: "Sign in with the Apple ID (secure password proof, the password itself is never sent).", comment: "Network audit purpose: the core's Apple ID sign-in start (SRP).")
        case "apple_id.request_sms":
            return String(localized: "Ask Apple to text the two-factor code.", comment: "Network audit purpose: the core's SMS code request.")
        case "apple_id.submit_code":
            return String(localized: "Send the two-factor code to finish signing in.", comment: "Network audit purpose: the core's two-factor code submission.")
        case "google.oauth.token":
            return String(localized: "Exchange the service account key for a short-lived access token.", comment: "Network audit purpose: the core's Google OAuth token exchange.")
        case "apple_session.select_team", "apple_session.portal_team":
            return String(localized: "Switch the Apple ID session to the account's team.", comment: "Network audit purpose: the core's Apple ID session team selection.")
        default:
            return nil
        }
    }

    private static func knownTitle(_ operation: String) -> String? {
        switch operation {
        case "provider.validate":
            return String(localized: "Account · check credentials", comment: "Network audit origin: the core's provider.validate.")
        case "provider.fetch_apps":
            return String(localized: "Account · load apps", comment: "Network audit origin: the core's provider.fetch_apps.")
        case "sync.sync_apps":
            return String(localized: "Sync · apps", comment: "Network audit origin: the core's sync.sync_apps.")
        case "apple_id.start":
            return String(localized: "Apple ID sign-in", comment: "Network audit origin: the core's apple_id.start.")
        case "apple_id.request_sms":
            return String(localized: "Apple ID sign-in · text the code", comment: "Network audit origin: the core's apple_id.request_sms.")
        case "apple_id.submit_code":
            return String(localized: "Apple ID sign-in · verify the code", comment: "Network audit origin: the core's apple_id.submit_code.")
        case "google.oauth.token":
            return String(localized: "Google · service account token", comment: "Network audit origin: the core's google.oauth.token.")
        case "apple_session.select_team":
            return String(localized: "Apple ID session · switch team", comment: "Network audit origin: the core's apple_session.select_team.")
        case "apple_session.portal_team":
            return String(localized: "Apple ID session · Developer Portal team", comment: "Network audit origin: the core's apple_session.portal_team.")
        case "unknown":
            return String(localized: "Unlisted core call", comment: "Network audit origin: a core exchange outside every documented operation.")
        default:
            return nil
        }
    }

    private static func areaTitle(_ handle: String) -> String? {
        switch handle {
        case "accessibility_declarations": return String(localized: "Accessibility", comment: "Network audit area: a core handle.")
        case "analytics": return String(localized: "Analytics Reports", comment: "Network audit area: a core handle.")
        case "app_details": return String(localized: "App Details", comment: "Network audit area: a core handle.")
        case "app_icons": return String(localized: "App Icons", comment: "Network audit area: a core handle.")
        case "app_metadata": return String(localized: "App Information", comment: "Network audit area: a core handle.")
        case "app_store_versions": return String(localized: "App Store Versions", comment: "Network audit area: a core handle.")
        case "beta_app_localizations", "beta_app_review_detail", "beta_build_localizations", "beta_groups":
            return "TestFlight"
        case "builds": return String(localized: "Builds", comment: "Network audit area: a core handle.")
        case "bundle_ids": return String(localized: "Identifiers", comment: "Network audit area: a core handle.")
        case "certificates": return String(localized: "Certificates", comment: "Network audit area: a core handle.")
        case "devices": return String(localized: "Devices", comment: "Network audit area: a core handle.")
        case "play_users": return String(localized: "Google Play Users", comment: "Network audit area: a core handle.")
        case "profiles": return String(localized: "Profiles", comment: "Network audit area: a core handle.")
        case "reviews": return String(localized: "Ratings and Reviews", comment: "Network audit area: a core handle.")
        case "store_listings": return String(localized: "Store Listings", comment: "Network audit area: a core handle.")
        case "tracks": return String(localized: "Google Play Releases", comment: "Network audit area: a core handle.")
        case "users": return String(localized: "Users and Access", comment: "Network audit area: a core handle.")
        default: return nil
        }
    }

    /// `fetch_customer_reviews` → `fetch customer reviews`.
    static func prettified(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " · ")
    }
}

// MARK: - Account names

/// Turns the core's account id into the account name the user gave.
protocol NetworkAuditAccountResolving: Sendable {
    func accountName(forCoreAccountId id: String) async -> String?
}

/// Maps the identifiers the core uses as `accountId` — the API key's issuer
/// ID, the Apple ID of a web session, a service account's `client_email`, a
/// Google login ID — to the names of the stored accounts. Several accounts
/// can share one (the teams of one Apple ID): their names are joined.
///
/// Built lazily on first use and dropped on every `accountsDidChange`.
actor NetworkAuditAccountDirectory: NetworkAuditAccountResolving {

    typealias AccountsLoader = @Sendable () async -> [(id: String, name: String, provider: ProviderType)]

    private let loadAccounts: AccountsLoader
    private let credentialIds: @Sendable (_ accountId: String, _ provider: ProviderType) -> [String]
    private var names: [String: String]?

    init(
        loadAccounts: @escaping AccountsLoader,
        credentialIds: @escaping @Sendable (_ accountId: String, _ provider: ProviderType) -> [String]
    ) {
        self.loadAccounts = loadAccounts
        self.credentialIds = credentialIds
    }

    /// The app's accounts (SwiftData) and their Keychain credentials.
    static func live(keychain: KeyStorable = KeychainStorable.shared) -> NetworkAuditAccountDirectory {
        nonisolated(unsafe) let keychain = keychain
        let directory = NetworkAuditAccountDirectory(
            loadAccounts: {
                guard let storage = await MainActor.run(body: { SwiftDataStorable.shared }) else { return [] }
                let accounts = (try? await storage.fetchAll(AccountModel.self)) ?? []
                return accounts.map { ($0.id, $0.name, $0.providerType) }
            },
            credentialIds: { accountId, provider in
                coreIds(accountId: accountId, provider: provider, keychain: keychain)
            }
        )
        NotificationCenter.default.addObserver(forName: .accountsDidChange, object: nil, queue: nil) { _ in
            Task { await directory.invalidate() }
        }
        return directory
    }

    static func coreIds(accountId: String, provider: ProviderType, keychain: KeyStorable) -> [String] {
        let key = "credentials.\(accountId)"
        switch provider {
        case .apple:
            guard let credentials: AppleCredentials = keychain.object(forKey: key) else { return [] }
            if let session = credentials.webSession { return [session.appleId] }
            return [credentials.issuerID]
        case .googlePlay:
            guard let credentials: GooglePlayCredentials = keychain.object(forKey: key) else { return [] }
            if let login = credentials.googleLoginId { return [login] }
            return (try? GooglePlayServiceAccount(credentials: credentials)).map { [$0.clientEmail] } ?? []
        case .firebase:
            return []
        }
    }

    func accountName(forCoreAccountId id: String) async -> String? {
        if names == nil {
            var built: [String: [String]] = [:]
            for account in await loadAccounts() {
                for coreId in credentialIds(account.id, account.provider) where !coreId.isEmpty {
                    built[coreId.lowercased(), default: []].append(account.name)
                }
            }
            names = built.mapValues { $0.sorted().joined(separator: ", ") }
        }
        return names?[id.lowercased()]
    }

    func invalidate() {
        names = nil
    }
}
