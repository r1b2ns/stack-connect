import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// The Apple ID session plumbing (plan `apple-id-sign-in.md` D3–D5, D7): the
/// shared Keychain item, its removal with the last account, the expiry
/// status, the connection's session path and the background skip.
@MainActor
final class AppleSessionTests: XCTestCase {

    private var keychain: MockKeyStorable!
    private var storage: MockPersistentStorable!
    private var status: MockAppleSessionStatus!

    private let appleId = "dev@example.com"

    override func setUp() async throws {
        try await super.setUp()
        keychain = MockKeyStorable()
        storage = MockPersistentStorable()
        status = MockAppleSessionStatus()
    }

    override func tearDown() async throws {
        keychain = nil
        storage = nil
        status = nil
        try await super.tearDown()
    }

    @discardableResult
    private func addSessionAccount(team: UInt64, appleId: String? = nil) async throws -> AccountModel {
        let account = AccountModel(name: "Team \(team)", providerType: .apple, authMethod: .appleIdSignIn)
        try await storage.save(account, id: account.id)
        keychain.setObject(
            AppleCredentials(webSession: .init(appleId: appleId ?? self.appleId, teamId: team, teamName: "Team \(team)")),
            forKey: "credentials.\(account.id)"
        )
        return account
    }

    // MARK: - Shared Keychain item

    func testEveryTeamAccountSharesTheAppleIdItem() {
        let store = AppleSessionKeychainStore(keychain: keychain)

        store.save(accountId: "Dev@Example.com ", blob: Data("one".utf8))

        XCTAssertEqual(keychain.storedKeys, ["appleSession.dev@example.com"])
        XCTAssertEqual(store.load(accountId: "dev@example.com"), Data("one".utf8))
        store.save(accountId: "dev@example.com", blob: Data("refreshed".utf8))
        XCTAssertEqual(keychain.storedKeys.count, 1, "a refresh from any team replaces the same item")
        XCTAssertEqual(store.load(accountId: "DEV@example.com"), Data("refreshed".utf8))
    }

    func testTheConnectionPassesTheAppleIdAndTeamToTheCore() async throws {
        let factory = SessionRecordingFactory()
        for team: UInt64 in [1, 2] {
            let connection = AppleAccountConnection(
                credentials: AppleCredentials(webSession: .init(appleId: "Dev@Example.com", teamId: team, teamName: "T")),
                connectivity: MockConnectivityProviding(online: true),
                coreProviders: factory,
                sessionStore: AppleSessionKeychainStore(keychain: keychain),
                sessionStatus: status
            )
            try await connection.validateCredentials()
        }

        XCTAssertEqual(factory.sessionCalls.map(\.accountId), [appleId, appleId], "one session key for every team")
        XCTAssertEqual(factory.sessionCalls.map(\.teamId), [1, 2])
        XCTAssertEqual(factory.apiKeyCalls, 0)
    }

    func testApiKeyAccountsKeepTheKeyPath() async throws {
        let factory = SessionRecordingFactory()
        let connection = AppleAccountConnection(
            credentials: AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "key"),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: factory,
            sessionStatus: status
        )

        try await connection.validateCredentials()

        XCTAssertEqual(factory.apiKeyCalls, 1)
        XCTAssertTrue(factory.sessionCalls.isEmpty)
    }

    func testSessionExpiredMarksTheAppleIdAndAWorkingCallClearsIt() async throws {
        let factory = SessionRecordingFactory()
        factory.validateError = StackError.SessionExpired(message: "401")
        let connection = AppleAccountConnection(
            credentials: AppleCredentials(webSession: .init(appleId: appleId, teamId: 1, teamName: "T")),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: factory,
            sessionStatus: status
        )

        do {
            try await connection.validateCredentials()
            XCTFail("expected SessionExpired")
        } catch {
            XCTAssertTrue(AppleAPIErrorTranslator.isSessionExpired(error))
            XCTAssertEqual(AppleAPIErrorTranslator.friendlyMessage(for: error), AppleAPIErrorTranslator.sessionExpiredMessage)
        }
        XCTAssertEqual(status.markedExpired, [appleId])

        factory.validateError = nil
        try await connection.validateCredentials()
        XCTAssertFalse(status.isExpired(appleId: appleId))
    }

    func testSessionExpiredOnAnApiKeyAccountMarksNothing() async {
        let factory = SessionRecordingFactory()
        factory.validateError = StackError.SessionExpired(message: "401")
        let connection = AppleAccountConnection(
            credentials: AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "key"),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: factory,
            sessionStatus: status
        )

        try? await connection.validateCredentials()

        XCTAssertTrue(status.markedExpired.isEmpty)
    }

    // MARK: - Removal with the last account

    func testDeletingTheLastAccountOfAnAppleIdRemovesItsSession() async throws {
        let first = try await addSessionAccount(team: 1)
        let second = try await addSessionAccount(team: 2)
        keychain.set(Data("blob".utf8), forKey: "appleSession.\(appleId)")
        status.markExpired(appleId: appleId)

        try await AccountCascadeDeleter.delete(first, storage: storage, keychain: keychain, appleSessionStatus: status)
        XCTAssertNotNil(keychain.data(forKey: "appleSession.\(appleId)"), "another team still uses it")

        try await AccountCascadeDeleter.delete(second, storage: storage, keychain: keychain, appleSessionStatus: status)
        XCTAssertNil(keychain.data(forKey: "appleSession.\(appleId)"))
        XCTAssertFalse(status.isExpired(appleId: appleId), "the expiry mark goes with it")
    }

    func testDeletingAnAccountKeepsOtherAppleIdsSessions() async throws {
        let mine = try await addSessionAccount(team: 1)
        try await addSessionAccount(team: 1, appleId: "other@example.com")
        keychain.set(Data("a".utf8), forKey: "appleSession.\(appleId)")
        keychain.set(Data("b".utf8), forKey: "appleSession.other@example.com")

        try await AccountCascadeDeleter.delete(mine, storage: storage, keychain: keychain, appleSessionStatus: status)

        XCTAssertNil(keychain.data(forKey: "appleSession.\(appleId)"))
        XCTAssertNotNil(keychain.data(forKey: "appleSession.other@example.com"))
    }

    // MARK: - Status store

    func testStatusStoreTracksExpiryAndPostsEachRefusal() throws {
        let suite = "AppleSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        var posted: [(String?, Bool?)] = []
        let token = center.addObserver(forName: .appleSessionDidExpire, object: nil, queue: nil) { note in
            posted.append((note.object as? String, note.userInfo?[AppleSessionStatusStore.isNewKey] as? Bool))
        }
        defer { center.removeObserver(token) }
        let store = AppleSessionStatusStore(defaults: defaults, center: center)

        store.markExpired(appleId: "Dev@Example.com")
        store.markExpired(appleId: "dev@example.com")

        XCTAssertTrue(store.isExpired(appleId: "DEV@example.com"))
        XCTAssertEqual(posted.map(\.0), [appleId, appleId])
        XCTAssertEqual(posted.map(\.1), [true, false])
        store.markValid(appleId: appleId)
        XCTAssertFalse(store.isExpired(appleId: appleId))
    }

    // MARK: - Background refresh (D7)

    func testBackgroundRefreshSkipsExpiredSessionAccounts() async throws {
        let expired = try await addSessionAccount(team: 1)
        let working = try await addSessionAccount(team: 2, appleId: "ok@example.com")
        let keyAccount = AccountModel(name: "Key", providerType: .apple)
        try await storage.save(keyAccount, id: keyAccount.id)
        keychain.setObject(AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "key"), forKey: "credentials.\(keyAccount.id)")
        status.markExpired(appleId: appleId)
        let suite = "AppleSessionTests.sync.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let analytics = MockAnalyticsTracker()
        var built: [AppleCredentials] = []
        let sut = StackConnect.SyncService(
            storage: storage,
            keychain: keychain,
            appleConnectionFactory: { credentials in
                built.append(credentials)
                return MockAppleAccountSyncing()
            },
            widgetSnapshotWriter: { _ in },
            firstAppsLoaded: FirstAppsLoadedTracker(defaults: UserDefaults(suiteName: suite) ?? .standard, analytics: analytics),
            analytics: analytics,
            appleSessionStatus: status
        )

        await sut.syncAll(mode: .lightweight).value

        XCTAssertEqual(sut.state.lastRunAccountCount, 2)
        XCTAssertFalse(built.contains { $0.webSession?.appleId == appleId }, "\(expired.name) is skipped")
        XCTAssertTrue(built.contains { $0.webSession?.appleId == "ok@example.com" }, "\(working.name) still syncs")

        built = []
        await sut.syncAll(mode: .full).value
        XCTAssertEqual(built.count, 3, "a foreground run still tries, which surfaces the prompt")
    }

    // MARK: - Credentials format

    func testApiKeyItemsWrittenBeforeSessionsDecodeUnchanged() throws {
        let legacy = #"{"issuerID":"i","privateKeyID":"k","privateKey":"p"}"#
        let credentials = try JSONDecoder().decode(AppleCredentials.self, from: Data(legacy.utf8))

        XCTAssertEqual(credentials.source, .apiKey)
        XCTAssertFalse(credentials.isWebSession)
        XCTAssertEqual(credentials.issuerID, "i")
    }

    func testSessionCredentialsRoundTrip() throws {
        let original = AppleCredentials(webSession: .init(appleId: " Dev@Example.com", teamId: 42, teamName: "Team"))
        let decoded = try JSONDecoder().decode(AppleCredentials.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.source, .webSession(.init(appleId: appleId, teamId: 42, teamName: "Team")))
        XCTAssertEqual(decoded.webSession?.appleId, appleId, "normalized")
    }

    // MARK: - Roles (AccountRules / role)

    func testPrimaryRoleIsTheMostCapable() {
        XCTAssertEqual(AccountRole.primary(fromAppStoreConnectRoles: ["DEVELOPER", "ADMIN"]), .admin)
        XCTAssertEqual(AccountRole.primary(fromAppStoreConnectRoles: ["ACCOUNT_HOLDER"]), .admin)
        XCTAssertEqual(AccountRole.primary(fromAppStoreConnectRoles: ["MARKETING", "APP_MANAGER"]), .appManager)
        XCTAssertEqual(AccountRole.primary(fromAppStoreConnectRoles: ["customer_support"]), .customerSupport)
        XCTAssertEqual(AccountRole.primary(fromAppStoreConnectRoles: ["CREATE_APPS"]), .unspecified)
    }

    func testRoleResolverMatchesTheSignedInUser() async {
        let users = StubUsersFetcher(users: [
            UserModel(id: "1", email: "someone@example.com", roles: ["ADMIN"], allAppsVisible: true, provisioningAllowed: true, isPending: false),
            UserModel(id: "2", email: "DEV@example.com", roles: ["DEVELOPER"], allAppsVisible: true, provisioningAllowed: false, isPending: false)
        ])
        let resolver = AppleSessionRoleResolver(makeUsersFetcher: { _ in users })

        let role = await resolver.role(of: appleId, in: .init(appleId: appleId, teamId: 1, teamName: "T"))

        XCTAssertEqual(role, .developer)
    }

    func testRoleResolverFallsBackToUnspecified() async {
        let resolver = AppleSessionRoleResolver(makeUsersFetcher: { _ in StubUsersFetcher(error: StackError.Http(status: 403, message: "")) })

        let role = await resolver.role(of: appleId, in: .init(appleId: appleId, teamId: 1, teamName: "T"))

        XCTAssertEqual(role, .unspecified)
    }

    func testCreatedSessionAccountsKeepEveryPermission() {
        let account = AccountModel(name: "T", providerType: .apple, authMethod: .appleIdSignIn)

        XCTAssertEqual(account.rules, .allPermissions, "App Store Connect enforces the user's roles")
    }

    // MARK: - Analytics category

    func testSessionExpiredIsAnInvalidCredentialsCategory() {
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: StackError.SessionExpired(message: "x")), .invalidCredentials)
    }
}

// MARK: - Doubles

/// Records which `connect` variant a connection used; optionally fails `validate`.
private final class SessionRecordingFactory: CoreProviderMaking, @unchecked Sendable {

    struct SessionCall: Equatable {
        let accountId: String
        let teamId: UInt64
    }

    private let lock = NSLock()
    private var _sessionCalls: [SessionCall] = []
    private var _apiKeyCalls = 0
    var validateError: StackError?

    var sessionCalls: [SessionCall] { lock.withLock { _sessionCalls } }
    var apiKeyCalls: Int { lock.withLock { _apiKeyCalls } }

    func connect(kind: ServiceKind, accountId: String, store: CredentialStore, debugLogger: DebugLogger?) throws -> StackCoreRust.Provider {
        lock.withLock { _apiKeyCalls += 1 }
        return ScriptedValidateProvider { [weak self] in self?.validateError }
    }

    func connectWithAccessToken(kind: ServiceKind, accountId: String, tokenProvider: AccessTokenProvider, debugLogger: DebugLogger?) throws -> StackCoreRust.Provider {
        throw StackError.Unsupported(message: "not used")
    }

    func connectWithAppleSession(accountId: String, teamId: UInt64, sessionStore: SessionStore, debugLogger: DebugLogger?) throws -> StackCoreRust.Provider {
        lock.withLock { _sessionCalls.append(SessionCall(accountId: accountId, teamId: teamId)) }
        return ScriptedValidateProvider { [weak self] in self?.validateError }
    }

    func makeSyncService(provider: StackCoreRust.Provider, store: BlobStore, accountId: String) -> StackCoreRust.SyncService {
        fatalError("not used")
    }
}

/// An App Store Connect provider whose `validate()` throws what `error` returns.
private final class ScriptedValidateProvider: FakeCoreProvider, @unchecked Sendable {
    private let error: () -> StackError?

    init(error: @escaping () -> StackError?) {
        self.error = error
        super.init(kind: .appStoreConnect)
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("never lifted")
    }

    override func validate() async throws {
        if let error = error() { throw error }
    }
}

private struct StubUsersFetcher: TeamUsersFetching {
    var users: [UserModel] = []
    var error: Error?

    func fetchUsers() async throws -> [UserModel] {
        if let error { throw error }
        return users
    }
}
