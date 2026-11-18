#if DEBUG
import Foundation
import StackCoreRust

/// Base class of the in-memory core providers.
///
/// UniFFI generates `Provider` (and every capability handle) as an `open class`
/// with an `init(noHandle:)` for fakes. **Any** method a fake does not override
/// would call into Rust with a null handle and crash, so this base overrides the
/// whole `Provider` surface with "unsupported" answers (`nil` capabilities, no
/// apps), and each service subclass (`FakeAppStoreConnectProvider`,
/// `FakeGooglePlayProvider`) overrides what its service offers. When the core is
/// re-vendored with a new `Provider` method, override it here too.
class FakeCoreProvider: StackCoreRust.Provider, @unchecked Sendable {

    private let serviceKind: ServiceKind

    init(kind: ServiceKind) {
        self.serviceKind = kind
        super.init(noHandle: .init())
    }

    /// Required by `Provider`: only used when the core hands an object back
    /// across the FFI, which never happens for an in-memory fake.
    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake core providers are never lifted from the FFI")
    }

    // MARK: - Metadata

    override func kind() -> ServiceKind { serviceKind }
    override func capabilities() -> [Capability] { [] }
    override func validate() async throws {}
    override func fetchApps() async throws -> [AppInfo] { [] }

    // MARK: - Capabilities (none by default)

    override func accessibilityDeclarations() -> AccessibilityDeclarations? { nil }
    override func analytics() -> Analytics? { nil }
    override func appDetails() -> AppDetails? { nil }
    override func appIcons() -> AppIcons? { nil }
    override func appMetadata() -> AppMetadata? { nil }
    override func appStoreVersions() -> AppStoreVersions? { nil }
    override func betaAppLocalizations() -> BetaAppLocalizations? { nil }
    override func betaAppReviewDetail() -> BetaAppReviewDetail? { nil }
    override func betaBuildLocalizations() -> BetaBuildLocalizations? { nil }
    override func betaGroups() -> BetaGroups? { nil }
    override func builds() -> Builds? { nil }
    override func bundleIds() -> BundleIds? { nil }
    override func certificates() -> Certificates? { nil }
    override func devices() -> Devices? { nil }
    override func playUsers() -> PlayUsers? { nil }
    override func profiles() -> Profiles? { nil }
    override func reviews() -> Reviews? { nil }
    override func storeListings() -> StoreListings? { nil }
    override func tracks() -> Tracks? { nil }
    override func users() -> Users? { nil }
}

/// The core's sync orchestrator, in memory: lists the provider's apps and
/// writes each one into the host `BlobStore` as the core's `"app"` blob
/// (`{id,name,bundleId,platform,accountId}`), exactly like
/// `SyncService.sync_apps()` in the Rust core.
final class FakeCoreSyncService: StackCoreRust.SyncService, @unchecked Sendable {

    private let provider: StackCoreRust.Provider
    private let store: BlobStore
    private let accountId: String

    init(provider: StackCoreRust.Provider, store: BlobStore, accountId: String) {
        self.provider = provider
        self.store = store
        self.accountId = accountId
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake sync services are never lifted from the FFI")
    }

    override func syncApps() async throws -> [AppInfo] {
        let apps = try await provider.fetchApps()
        let blobs: [(id: String, json: String)] = apps.compactMap { app in
            let blob = CoreAppBlob(id: app.id, name: app.name, bundleId: app.bundleId, platform: app.platform, accountId: accountId)
            guard let data = try? JSONEncoder().encode(blob), let json = String(data: data, encoding: .utf8) else { return nil }
            return (app.id, json)
        }
        // The host store blocks on its async storage (it expects to be called
        // from the core's own threads), so write from a plain dispatch thread,
        // never from the Swift concurrency pool.
        let store = self.store
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                for blob in blobs {
                    store.save(typeName: "app", id: blob.id, json: blob.json)
                }
                continuation.resume()
            }
        }
        return apps
    }
}

/// `CoreProviderMaking` for fake data mode: routes each `connect` to the
/// in-memory account it names (App Store Connect: issuer ID; Google Play:
/// service-account e-mail). An unknown account gets an empty one, so adding a
/// new account in fake mode works too.
final class FakeCoreProviderFactory: CoreProviderMaking, @unchecked Sendable {

    let appStoreConnect: FakeAppStoreConnectBackend
    let googlePlay: FakeGooglePlayBackend

    init(appStoreConnect: FakeAppStoreConnectBackend, googlePlay: FakeGooglePlayBackend) {
        self.appStoreConnect = appStoreConnect
        self.googlePlay = googlePlay
    }

    func connect(
        kind: ServiceKind,
        accountId: String,
        store: CredentialStore,
        debugLogger: DebugLogger?
    ) throws -> StackCoreRust.Provider {
        switch kind {
        case .appStoreConnect:
            return FakeAppStoreConnectProvider(team: appStoreConnect.team(issuerId: accountId))
        case .googlePlay:
            return FakeGooglePlayProvider(developer: googlePlay.developer(clientEmail: accountId))
        }
    }

    /// A Google sign-in account (`accountId` is its login ID) gets the fake
    /// developer of that ID: an empty one unless seeded under it.
    func connectWithAccessToken(
        kind: ServiceKind,
        accountId: String,
        tokenProvider: AccessTokenProvider,
        debugLogger: DebugLogger?
    ) throws -> StackCoreRust.Provider {
        switch kind {
        case .appStoreConnect:
            throw StackError.Unsupported(message: "App Store Connect has no access-token auth path.")
        case .googlePlay:
            return FakeGooglePlayProvider(developer: googlePlay.developer(clientEmail: accountId))
        }
    }

    func makeSyncService(
        provider: StackCoreRust.Provider,
        store: BlobStore,
        accountId: String
    ) -> StackCoreRust.SyncService {
        FakeCoreSyncService(provider: provider, store: store, accountId: accountId)
    }
}
#endif
