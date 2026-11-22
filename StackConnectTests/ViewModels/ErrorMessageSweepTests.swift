import XCTest
import StackCoreRust
import APIProviderFirebase
@testable import StackConnect

/// Guards the app-wide error sweep: screens that load from App Store
/// Connect, Firebase or Google Play show a server refusal as its readable
/// title and detail — never the core's debug dump
/// (`StackCoreRust.StackError.Http(status: 403, message: "{\n  \"errors\" …")`).
///
/// The App Store Connect screens build their `AppleAccountConnection`
/// inline, so the Rust core factory itself is swapped
/// (`BackendEnvironment.coreProviders`) for one whose `connect` fails with
/// the 403 body every Apple call would get.
@MainActor
final class ErrorMessageSweepTests: XCTestCase {

    private typealias Body = UserFacingErrorMapperTests

    private var previousCoreProviders: (any CoreProviderMaking)!
    private var previousFirebaseProviders: (any FirebaseProviderMaking)!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private let account = AccountModel(id: "asc.sweep", name: "ASC", providerType: .apple)

    override func setUp() async throws {
        try await super.setUp()
        previousCoreProviders = BackendEnvironment.coreProviders
        previousFirebaseProviders = BackendEnvironment.firebaseProviders
        BackendEnvironment.coreProviders = FailingCoreProviderFactory(error: Body.asc403)
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        keychain.setObject(
            AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "key"),
            forKey: "credentials.\(account.id)"
        )
    }

    override func tearDown() async throws {
        BackendEnvironment.coreProviders = previousCoreProviders
        BackendEnvironment.firebaseProviders = previousFirebaseProviders
        previousCoreProviders = nil
        previousFirebaseProviders = nil
        keychain = nil
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - App Store Connect: provisioning

    func testCertificatesShowTheServerTitleAndDetail() async {
        let sut = CertificatesListViewModel(account: account, keychain: keychain, analytics: analytics)
        await sut.load()
        assertShowsTheASCRefusal(sut.uiState.errorMessage)
    }

    func testProfilesShowTheServerTitleAndDetail() async {
        let sut = ProfilesListViewModel(account: account, keychain: keychain, analytics: analytics)
        await sut.load()
        assertShowsTheASCRefusal(sut.uiState.errorMessage)
    }

    func testDevicesShowTheServerTitleAndDetail() async {
        let sut = DevicesListViewModel(account: account, keychain: keychain, analytics: analytics)
        await sut.load()
        assertShowsTheASCRefusal(sut.uiState.errorMessage)
    }

    func testIdentifiersShowTheServerTitleAndDetail() async {
        let sut = IdentifiersListViewModel(account: account, keychain: keychain, analytics: analytics)
        await sut.load()
        assertShowsTheASCRefusal(sut.uiState.errorMessage)
    }

    // MARK: - App Store Connect: apps, builds, TestFlight, users

    func testAppListSyncShowsTheServerTitleAndDetail() async {
        let sut = AppListViewModel(
            account: account,
            storage: MockPersistentStorable(),
            keychain: keychain,
            analytics: analytics,
            statusProvider: MockAccountStatusProvider()
        )
        await sut.loadApps()
        assertShowsTheASCRefusal(sut.uiState.syncError)
    }

    func testAppHistoryShowsTheServerTitleAndDetail() async {
        let sut = AppHistoryViewModel(appId: "123", account: account, keychain: keychain, analytics: analytics)
        await sut.load()
        assertShowsTheASCRefusal(sut.uiState.error)
    }

    func testPlatformBuildsShowTheServerTitleAndDetail() async {
        let sut = PlatformBuildsViewModel(appId: "123", platform: "IOS", account: account, keychain: keychain, analytics: analytics)
        await sut.load()
        assertShowsTheASCRefusal(sut.uiState.error)
    }

    func testTestFlightShowsTheServerTitleAndDetail() async {
        let sut = TestFlightViewModel(appId: "123", account: account, keychain: keychain, analytics: analytics)
        await sut.load()
        assertShowsTheASCRefusal(sut.uiState.error)
    }

    func testUserAccessShowsTheServerTitleAndDetail() async {
        let sut = UserAccessViewModel(account: account, keychain: keychain, analytics: analytics)
        await sut.load()
        assertShowsTheASCRefusal(sut.uiState.error)
    }

    // MARK: - Reviews

    func testAppStoreReviewsLoadMessageShowsTheServerTitleAndDetail() {
        let service = AppleCustomerReviewsService(connection: MockAppleReviewsConnection())
        assertShowsTheASCRefusal(service.message(for: Body.asc403, operation: .load))
    }

    // MARK: - Firebase

    func testFirebaseProjectsShowGooglesMessage() async {
        let googleMessage = "The caller does not have permission"
        let executor = ScriptedFirebaseExecutor { _ in
            (403, #"{"error": {"code": 403, "status": "PERMISSION_DENIED", "message": "The caller does not have permission"}}"#)
        }
        BackendEnvironment.firebaseProviders = ScriptedFirebaseProviderFactory(executor: executor)
        let firebaseAccount = GoogleSignInFirebaseFixtures.account()
        GoogleSignInFirebaseFixtures.storeCredentials(for: firebaseAccount, in: keychain)
        let sut = FirebaseProjectListViewModel(
            account: firebaseAccount,
            keychain: keychain,
            analytics: analytics,
            googleAuth: GoogleSignInFirebaseFixtures.auth()
        )

        await sut.load()

        XCTAssertEqual(sut.uiState.error, googleMessage)
        assertReadable(sut.uiState.error)
    }

    // MARK: - Google Play

    func testGooglePlayUsersShowTheServerTitleAndDetail() async throws {
        let storage = MockPersistentStorable()
        let connection = MockGooglePlayUsersConnection(users: [])
        let playAccount = AccountModel(id: "play.sweep", name: "Play", providerType: .googlePlay, googlePlayDeveloperId: "4829103756618820931")
        try await storage.save(playAccount, id: playAccount.id)
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
                           forKey: "credentials.\(playAccount.id)")
        connection.failNext(.fetch, with: Body.asc403)
        let sut = GooglePlayUsersViewModel(account: playAccount, keychain: keychain, storage: storage,
                                           connectionFactory: connection.factory, analytics: analytics)

        await sut.load()

        assertShowsTheASCRefusal(sut.uiState.error)
    }

    // MARK: - Helpers

    private func assertShowsTheASCRefusal(_ message: String?, file: StaticString = #filePath, line: UInt = #line) {
        guard let message else {
            return XCTFail("no error message", file: file, line: line)
        }
        XCTAssertTrue(message.contains(Body.ascTitle), "title missing in: \(message)", file: file, line: line)
        XCTAssertTrue(message.contains(Body.ascDetail), "detail missing in: \(message)", file: file, line: line)
        assertReadable(message, file: file, line: line)
    }

    private func assertReadable(_ message: String?, file: StaticString = #filePath, line: UInt = #line) {
        guard let message else {
            return XCTFail("no error message", file: file, line: line)
        }
        XCTAssertFalse(message.contains("{"), "JSON in: \(message)", file: file, line: line)
        XCTAssertFalse(message.contains("StackError"), "type name in: \(message)", file: file, line: line)
        XCTAssertFalse(message.contains("\\n"), "escape sequence in: \(message)", file: file, line: line)
    }
}

// MARK: - Doubles

/// A Rust core whose every connection fails with `error` (the shape an App
/// Store Connect refusal takes for any call the screen would make).
private struct FailingCoreProviderFactory: CoreProviderMaking {

    let error: StackError

    func connect(kind: ServiceKind, accountId: String, store: CredentialStore, debugLogger: DebugLogger?) throws -> StackCoreRust.Provider {
        throw error
    }

    func connectWithAccessToken(kind: ServiceKind, accountId: String, tokenProvider: AccessTokenProvider, debugLogger: DebugLogger?) throws -> StackCoreRust.Provider {
        throw error
    }

    func connectWithAppleSession(accountId: String, teamId: UInt64, sessionStore: SessionStore, debugLogger: DebugLogger?) throws -> StackCoreRust.Provider {
        throw error
    }

    /// Only reached with a connected provider, which this factory never hands out.
    func makeSyncService(provider: StackCoreRust.Provider, store: BlobStore, accountId: String) -> StackCoreRust.SyncService {
        FakeCoreSyncService(provider: provider, store: store, accountId: accountId)
    }
}
