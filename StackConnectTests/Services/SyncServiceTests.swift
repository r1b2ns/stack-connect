import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

@MainActor
final class SyncServiceTests: XCTestCase {

    private var sut: StackConnect.SyncService!
    private var mockStorage: MockPersistentStorable!
    private var mockKeychain: MockKeyStorable!
    private var connections: [String: MockAppleAccountSyncing] = [:]
    private var playConnection: MockGooglePlayAccountConnection!
    private var snapshotWrites = 0
    private var analytics: MockAnalyticsTracker!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        mockStorage = MockPersistentStorable()
        mockKeychain = MockKeyStorable()
        connections = [:]
        snapshotWrites = 0
        let playConnection = MockGooglePlayAccountConnection()
        self.playConnection = playConnection
        analytics = MockAnalyticsTracker()
        defaultsSuiteName = "SyncServiceTests.\(UUID().uuidString)"
        let firstAppsLoaded = FirstAppsLoadedTracker(
            defaults: UserDefaults(suiteName: defaultsSuiteName) ?? .standard,
            analytics: analytics
        )
        sut = StackConnect.SyncService(
            storage: mockStorage,
            keychain: mockKeychain,
            appleConnectionFactory: { [weak self] credentials in
                self?.connections[credentials.issuerID] ?? MockAppleAccountSyncing()
            },
            googlePlayConnectionFactory: playConnection.syncFactory,
            widgetSnapshotWriter: { [weak self] _ in self?.snapshotWrites += 1 },
            firstAppsLoaded: firstAppsLoaded,
            analytics: analytics
        )
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        analytics = nil
        sut = nil
        mockStorage = nil
        mockKeychain = nil
        playConnection = nil
        try await super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertFalse(sut.state.isSyncing)
        XCTAssertTrue(sut.state.accountsInProgress.isEmpty)
        XCTAssertNil(sut.state.lastSyncedAt)
        XCTAssertNil(sut.state.lastError)
    }

    // MARK: - No-op flows

    func testSyncAllWithNoAccountsCompletesAndStampsTimestamp() async {
        await sut.syncAll().value

        XCTAssertFalse(sut.state.isSyncing)
        XCTAssertNotNil(sut.state.lastSyncedAt)
        XCTAssertNil(sut.state.lastError)
        XCTAssertTrue(sut.state.accountsInProgress.isEmpty)
    }

    func testSyncAllSkipsFirebaseAccounts() async throws {
        let firebase = AccountModel(name: "Firebase", providerType: .firebase)
        try await mockStorage.save(firebase, id: firebase.id)

        await sut.syncAll().value

        // No SyncMetadata persisted because Firebase has nothing to sync.
        let metadataFirebase: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(firebase.id)"
        )
        XCTAssertNil(metadataFirebase)
        XCTAssertNotNil(sut.state.lastSyncedAt)
    }

    // MARK: - Google Play leg (plan S1)

    func testSyncAllRunsGooglePlayAccounts() async throws {
        let play = AccountModel(name: "Play", providerType: .googlePlay)
        try await mockStorage.save(play, id: play.id)
        mockKeychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(play.id)"
        )
        playConnection.fetchAppsHandler = {
            [StackProtocols.AppInfo(id: "com.play", name: "Play App", bundleId: "com.play", platform: "ANDROID")]
        }

        await sut.syncAll().value

        let list: [GooglePlayAppItem]? = try await mockStorage.fetch(
            [GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: play.id)
        )
        XCTAssertEqual(list?.map(\.packageName), ["com.play"])
        let metadata: SyncMetadata? = try await mockStorage.fetch(SyncMetadata.self, id: "sync.account.\(play.id)")
        XCTAssertEqual(metadata?.appsSynced, 1)
        XCTAssertEqual(playConnection.editBasedReadCount, 0)
        XCTAssertTrue(sut.state.accountsInProgress.isEmpty)
        XCTAssertEqual(sut.state.providerByAccountId[play.id], .googlePlay)
    }

    // MARK: - Activation (first_apps_loaded)

    func testFirstSuccessfulSyncWithAppsSendsFirstAppsLoadedOnce() async throws {
        let play = AccountModel(name: "Play", providerType: .googlePlay)
        try await mockStorage.save(play, id: play.id)
        mockKeychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(play.id)"
        )
        playConnection.fetchAppsHandler = {
            [
                StackProtocols.AppInfo(id: "com.a", name: "A", bundleId: "com.a", platform: "ANDROID"),
                StackProtocols.AppInfo(id: "com.b", name: "B", bundleId: "com.b", platform: "ANDROID")
            ]
        }

        await sut.syncAll().value
        await sut.syncAll().value

        XCTAssertEqual(analytics.actions(of: .firstAppsLoaded), [
            .action(.firstAppsLoaded, on: .home, parameters: [
                AnalyticsParameterKey.count: .int(2),
                AnalyticsParameterKey.kind: .string("googlePlay")
            ])
        ])
    }

    func testSyncWithoutAppsDoesNotSendFirstAppsLoaded() async throws {
        let play = AccountModel(name: "Play", providerType: .googlePlay)
        try await mockStorage.save(play, id: play.id)

        await sut.syncAll().value

        XCTAssertTrue(analytics.actions(of: .firstAppsLoaded).isEmpty)
    }

    func testGooglePlayAccountWithMissingCredentialsRecordsError() async throws {
        let play = AccountModel(name: "Play", providerType: .googlePlay)
        try await mockStorage.save(play, id: play.id)

        await sut.syncAll().value

        let metadata: SyncMetadata? = try await mockStorage.fetch(SyncMetadata.self, id: "sync.account.\(play.id)")
        XCTAssertNotNil(metadata?.lastError)
        XCTAssertEqual(playConnection.fetchAppsCallCount, 0)
    }

    func testFailingGooglePlayAccountDoesNotStopAppleAccounts() async throws {
        let play = AccountModel(name: "Play", providerType: .googlePlay)
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(play, id: play.id)
        try await mockStorage.save(apple, id: apple.id)
        mockKeychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(play.id)"
        )
        playConnection.fetchAppsHandler = { throw URLError(.notConnectedToInternet) }
        setCredentials(issuerID: "issuer-1", for: apple)
        let connection = MockAppleAccountSyncing()
        connection.apps = [StackProtocols.AppInfo(id: "app-1", name: "App One", bundleId: "com.one", platform: nil)]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let playMetadata: SyncMetadata? = try await mockStorage.fetch(SyncMetadata.self, id: "sync.account.\(play.id)")
        let appleMetadata: SyncMetadata? = try await mockStorage.fetch(SyncMetadata.self, id: "sync.account.\(apple.id)")
        XCTAssertNotNil(playMetadata?.lastError)
        XCTAssertNil(appleMetadata?.lastError)
        XCTAssertEqual(appleMetadata?.appsSynced, 1)
    }

    func testEverySyncRewritesTheWidgetSnapshot() async throws {
        await sut.syncAll().value
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(apple, id: apple.id)
        await sut.syncAll().value

        XCTAssertEqual(snapshotWrites, 2)
    }

    func testInProgressCountsArePerProvider() {
        var state = SyncState()
        state.providerByAccountId = ["a": .apple, "b": .apple, "c": .googlePlay]
        state.accountsInProgress = ["a", "b", "c"]
        XCTAssertEqual(state.inProgressCountByProvider, [.apple: 2, .googlePlay: 1])
    }

    // MARK: - Missing credentials

    func testAppleAccountWithMissingCredentialsRecordsError() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(apple, id: apple.id)

        await sut.syncAll().value

        let metadata: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(apple.id)"
        )
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.accountId, apple.id)
        XCTAssertEqual(metadata?.appsSynced, 0)
        XCTAssertNotNil(metadata?.lastError)
    }

    func testFailedAccountIsReportedInRunStateWithoutRunLevelError() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(apple, id: apple.id)

        await sut.syncAll(mode: .lightweight).value

        XCTAssertNil(sut.state.lastError)
        XCTAssertEqual(sut.state.lastRunMode, .lightweight)
        XCTAssertEqual(sut.state.lastRunAccountCount, 1)
        XCTAssertEqual(sut.state.lastRunFailedAccountCount, 1)
        XCTAssertFalse(sut.state.lastRunSucceeded)
    }

    func testRunWithoutAccountsSucceedsWithZeroAccounts() async {
        await sut.syncAll().value

        XCTAssertEqual(sut.state.lastRunMode, .full)
        XCTAssertEqual(sut.state.lastRunAccountCount, 0)
        XCTAssertEqual(sut.state.lastRunFailedAccountCount, 0)
        XCTAssertTrue(sut.state.lastRunSucceeded)
    }

    // MARK: - Coalescing

    func testConcurrentSyncAllCallsAreCoalesced() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(apple, id: apple.id)

        let task1 = sut.syncAll()
        let task2 = sut.syncAll()

        await task1.value
        await task2.value

        // One fetch for accounts means only one performSyncAll ran.
        let counts = await mockStorage.fetchAllCallCount
        XCTAssertEqual(counts[String(describing: AccountModel.self)], 1)
    }

    func testSequentialSyncAllCallsBothExecute() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(apple, id: apple.id)

        await sut.syncAll().value
        await sut.syncAll().value

        let counts = await mockStorage.fetchAllCallCount
        XCTAssertEqual(counts[String(describing: AccountModel.self)], 2)
    }

    // MARK: - State transitions

    func testStateClearsAccountsInProgressAfterSync() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(apple, id: apple.id)

        await sut.syncAll().value

        XCTAssertTrue(sut.state.accountsInProgress.isEmpty)
        XCTAssertFalse(sut.state.isSyncing)
    }

    // MARK: - Happy path (with mock connection)

    func testSyncPersistsAppsWithEnrichmentForSingleAccount() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.apps = [
            StackProtocols.AppInfo(id: "app-1", name: "App One", bundleId: "com.one", platform: nil),
            StackProtocols.AppInfo(id: "app-2", name: "App Two", bundleId: "com.two", platform: nil)
        ]
        connection.iconUrls = ["app-1": "https://icons/1.png", "app-2": "https://icons/2.png"]
        connection.versions = [
            "app-1": [makeVersion(id: "v1", appId: "app-1", state: .waitingForReview, versionString: "1.0.0")],
            "app-2": [makeVersion(id: "v2", appId: "app-2", state: .readyForSale, versionString: "2.0.0")]
        ]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let saved1: AppModel? = try await mockStorage.fetch(AppModel.self, id: "\(account.id).app-1")
        let saved2: AppModel? = try await mockStorage.fetch(AppModel.self, id: "\(account.id).app-2")

        XCTAssertEqual(saved1?.name, "App One")
        XCTAssertEqual(saved1?.iconUrl, "https://icons/1.png")
        XCTAssertEqual(saved1?.appStoreState, .waitingForReview)
        XCTAssertEqual(saved1?.versionString, "1.0.0")
        XCTAssertTrue(saved1?.hasReviewPending ?? false)

        XCTAssertEqual(saved2?.appStoreState, .readyForSale)
        XCTAssertEqual(saved2?.versionString, "2.0.0")
        XCTAssertFalse(saved2?.hasReviewPending ?? true)

        let metadata: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(account.id)"
        )
        XCTAssertEqual(metadata?.appsSynced, 2)
        XCTAssertNil(metadata?.lastError)
    }

    func testSyncRunsAccountsInParallelAndKeepsTheirDataIsolated() async throws {
        let accountA = AccountModel(name: "A", providerType: .apple)
        let accountB = AccountModel(name: "B", providerType: .apple)
        try await mockStorage.save(accountA, id: accountA.id)
        try await mockStorage.save(accountB, id: accountB.id)
        setCredentials(issuerID: "issuer-A", for: accountA)
        setCredentials(issuerID: "issuer-B", for: accountB)

        let connA = MockAppleAccountSyncing()
        connA.apps = [StackProtocols.AppInfo(id: "a1", name: "A1", bundleId: "com.a1", platform: nil)]
        connections["issuer-A"] = connA

        let connB = MockAppleAccountSyncing()
        connB.apps = [
            StackProtocols.AppInfo(id: "b1", name: "B1", bundleId: "com.b1", platform: nil),
            StackProtocols.AppInfo(id: "b2", name: "B2", bundleId: "com.b2", platform: nil)
        ]
        connections["issuer-B"] = connB

        await sut.syncAll().value

        let metadataA: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(accountA.id)"
        )
        let metadataB: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(accountB.id)"
        )
        XCTAssertEqual(metadataA?.appsSynced, 1)
        XCTAssertEqual(metadataB?.appsSynced, 2)

        XCTAssertEqual(connA.fetchedAppListCount, 1)
        XCTAssertEqual(connB.fetchedAppListCount, 1)

        // Optimization (#84 follow-up): validate up front exactly once per account,
        // before the concurrent enrichment task group — never once per app.
        XCTAssertEqual(connA.validateCredentialsCount, 1)
        XCTAssertEqual(connB.validateCredentialsCount, 1)
    }

    // MARK: - Validate-once optimization (#84 follow-up)

    func testSyncValidatesCredentialsExactlyOncePerAccount() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        // Several apps would each spawn a concurrent enrichment task; the up-front
        // validate must still fire only once for the whole account.
        connection.apps = [
            StackProtocols.AppInfo(id: "app-1", name: "App One", bundleId: "com.one", platform: nil),
            StackProtocols.AppInfo(id: "app-2", name: "App Two", bundleId: "com.two", platform: nil),
            StackProtocols.AppInfo(id: "app-3", name: "App Three", bundleId: "com.three", platform: nil)
        ]
        connection.versions = [
            "app-1": [makeVersion(id: "v1", appId: "app-1", state: .readyForSale, versionString: "1.0")],
            "app-2": [makeVersion(id: "v2", appId: "app-2", state: .readyForSale, versionString: "1.0")],
            "app-3": [makeVersion(id: "v3", appId: "app-3", state: .readyForSale, versionString: "1.0")]
        ]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        XCTAssertEqual(connection.validateCredentialsCount, 1,
                       "validateCredentials must run exactly once per account, before enrichment")
    }

    func testValidateCredentialsFailureRecordsErrorAndSkipsFetch() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.validateCredentialsError = makeError(status: 401, code: "NOT_AUTHORIZED", detail: "Bad key")
        connections["issuer-1"] = connection

        await sut.syncAll().value

        // The up-front validate throws, so fetchApps must never run...
        XCTAssertEqual(connection.validateCredentialsCount, 1)
        XCTAssertEqual(connection.fetchedAppListCount, 0)

        // ...and the existing do/catch persists metadata with the error.
        let metadata: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(account.id)"
        )
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.appsSynced, 0)
        XCTAssertNotNil(metadata?.lastError)
    }

    func testArchivedAppsAreNotEnriched() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        // Pre-cache one of the apps as archived.
        let archivedApp = AppModel(
            id: "archived-app",
            name: "Archived",
            bundleId: "com.archived",
            accountId: account.id,
            isArchived: true
        )
        try await mockStorage.save(archivedApp, id: "\(account.id).archived-app")

        let connection = MockAppleAccountSyncing()
        connection.apps = [
            StackProtocols.AppInfo(id: "archived-app", name: "Archived", bundleId: "com.archived", platform: nil),
            StackProtocols.AppInfo(id: "active-app", name: "Active", bundleId: "com.active", platform: nil)
        ]
        connection.versions = [
            "active-app": [makeVersion(id: "va", appId: "active-app", state: .readyForSale, versionString: "1.0")]
        ]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        XCTAssertFalse(connection.fetchedVersionsForAppIds.contains("archived-app"),
                       "Archived apps must not trigger version enrichment")
        XCTAssertTrue(connection.fetchedVersionsForAppIds.contains("active-app"))
    }

    func testLightweightModeSyncsReviewsAndEnrichesApps() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.apps = [
            StackProtocols.AppInfo(id: "app-1", name: "App One", bundleId: "com.one", platform: nil)
        ]
        connection.versions = [
            "app-1": [makeVersion(id: "v1", appId: "app-1", state: .readyForSale, versionString: "1.0")]
        ]
        connection.reviews = [
            "app-1": [
                CustomerReviewModel(id: "r1", rating: 5, title: "Great", body: nil,
                                    reviewerNickname: nil, createdDate: .now, territory: nil,
                                    responseId: nil, responseBody: nil, responseState: nil,
                                    responseDate: nil, appId: nil)
            ]
        ]
        connections["issuer-1"] = connection

        await sut.syncAll(mode: .lightweight).value

        XCTAssertTrue(connection.fetchedVersionsForAppIds.contains("app-1"),
                      "Lightweight mode must still enrich apps")
        XCTAssertTrue(connection.fetchedReviewsForAppIds.contains("app-1"),
                      "Lightweight mode must also re-sync reviews to keep the widget fresh")

        let cachedReview: CustomerReviewModel? = try await mockStorage.fetch(
            CustomerReviewModel.self, id: "review.app-1.r1"
        )
        XCTAssertNotNil(cachedReview, "Reviews should be persisted in lightweight mode")
    }

    func testSyncWithNoAppsRecordsZeroAppsSynced() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.apps = []
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let metadata: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(account.id)"
        )
        XCTAssertEqual(metadata?.appsSynced, 0)
        XCTAssertNil(metadata?.lastError)
    }

    // MARK: - Pending Agreements

    func testAgreementErrorSetsPendingFlagAndTimestamp() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.fetchAppsError = makeAgreementError()
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let updated: AccountModel? = try await mockStorage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(updated?.hasPendingAgreements, true)
        XCTAssertNotNil(updated?.pendingAgreementsDetectedAt)
    }

    func testNonAgreement403LeavesPendingFlagFalse() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.fetchAppsError = makeError(status: 403, code: "FORBIDDEN_ERROR", detail: "Not permitted")
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let updated: AccountModel? = try await mockStorage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(updated?.hasPendingAgreements, false)
        XCTAssertNil(updated?.pendingAgreementsDetectedAt)
    }

    func testCleanSyncClearsPreviouslySetPendingFlag() async throws {
        let account = AccountModel(
            name: "Apple",
            providerType: .apple,
            hasPendingAgreements: true,
            pendingAgreementsDetectedAt: Date(timeIntervalSince1970: 1_000)
        )
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.apps = [StackProtocols.AppInfo(id: "app-1", name: "App One", bundleId: "com.one", platform: nil)]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let updated: AccountModel? = try await mockStorage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(updated?.hasPendingAgreements, false)
        XCTAssertNil(updated?.pendingAgreementsDetectedAt)
    }

    func testTransientErrorDoesNotClearPreviouslySetPendingFlag() async throws {
        let detectedAt = Date(timeIntervalSince1970: 1_000)
        let account = AccountModel(
            name: "Apple",
            providerType: .apple,
            hasPendingAgreements: true,
            pendingAgreementsDetectedAt: detectedAt
        )
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.fetchAppsError = makeError(status: 500, code: "INTERNAL_ERROR", detail: "Server down")
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let updated: AccountModel? = try await mockStorage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(updated?.hasPendingAgreements, true)
        XCTAssertEqual(updated?.pendingAgreementsDetectedAt, detectedAt)
    }

    // MARK: - Phased release (per-platform)

    /// The reported bug at the sync layer: an app whose overall-latest version is
    /// iOS (readyForSale, no phased) also ships a tvOS version that is
    /// readyForSale with an active phased release. Sync must fetch the phased
    /// release using the *tvOS* version's own id and store it under
    /// "phased.{tvOSVersionId}", not the app id.
    func testSyncFetchesAndStoresPhasedPerPlatformVersion() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.apps = [
            StackProtocols.AppInfo(id: "app-1", name: "Multi", bundleId: "com.multi", platform: nil)
        ]
        // iOS is the most-recent version overall; tvOS is older but still awaiting.
        connection.versions = [
            "app-1": [
                makePlatformVersion(id: "v-ios", appId: "app-1", platform: .ios, state: .readyForSale, createdOffset: 0),
                makePlatformVersion(id: "v-tv", appId: "app-1", platform: .tvOs, state: .readyForSale, createdOffset: -100)
            ]
        ]
        // Only the tvOS version is phasing.
        connection.phasedReleases = [
            "v-tv": PhasedReleaseModel(id: "phased.v-tv", state: .active, currentDayNumber: 3)
        ]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        // Both awaiting-eligible version ids were queried for phased data.
        XCTAssertTrue(connection.fetchedPhasedForVersionIds.contains("v-ios"))
        XCTAssertTrue(connection.fetchedPhasedForVersionIds.contains("v-tv"))

        // The tvOS phased release is stored under the version-id key.
        let phasedTv: PhasedReleaseModel? = try await mockStorage.fetch(
            PhasedReleaseModel.self, id: "phased.v-tv"
        )
        XCTAssertEqual(phasedTv?.state, .active)
        XCTAssertEqual(phasedTv?.currentDayNumber, 3)

        // The persisted app carries the per-platform version ids so the widgets
        // can resolve phased per platform.
        let saved: AppModel? = try await mockStorage.fetch(AppModel.self, id: "\(account.id).app-1")
        let byPlatform = Dictionary(
            uniqueKeysWithValues: (saved?.platformVersions ?? []).map { ($0.platform, $0.id) }
        )
        XCTAssertEqual(byPlatform[AppPlatform.ios.rawValue] ?? nil, "v-ios")
        XCTAssertEqual(byPlatform[AppPlatform.tvOs.rawValue] ?? nil, "v-tv")
    }

    // MARK: - Per-platform icons (multi-platform apps)

    /// A multi-platform app (versions on ≥2 platforms) triggers a builds fetch and
    /// persists each platform version's icon resolved from that platform's build.
    func testMultiPlatformAppFetchesBuildsAndPersistsPerPlatformIcons() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.apps = [
            StackProtocols.AppInfo(id: "app-1", name: "Multi", bundleId: "com.multi", platform: nil)
        ]
        connection.versions = [
            "app-1": [
                makePlatformVersion(id: "v-ios", appId: "app-1", platform: .ios, state: .readyForSale, createdOffset: 0),
                makePlatformVersion(id: "v-tv", appId: "app-1", platform: .tvOs, state: .readyForSale, createdOffset: -100)
            ]
        ]
        connection.builds = [
            "app-1": [
                makeBuild(id: "b-ios", platform: .ios, iconUrl: "https://cdn/ios.png"),
                makeBuild(id: "b-tv", platform: .tvOs, iconUrl: "https://cdn/tv.png")
            ]
        ]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        // The multi-platform app triggers a builds fetch.
        XCTAssertTrue(connection.fetchedBuildsForAppIds.contains("app-1"))

        // Each per-platform version carries its own resolved icon.
        let saved: AppModel? = try await mockStorage.fetch(AppModel.self, id: "\(account.id).app-1")
        let iconByPlatform = Dictionary(
            uniqueKeysWithValues: (saved?.platformVersions ?? []).map { ($0.platform, $0.iconUrl) }
        )
        XCTAssertEqual(iconByPlatform[AppPlatform.ios.rawValue] ?? nil, "https://cdn/ios.png")
        XCTAssertEqual(iconByPlatform[AppPlatform.tvOs.rawValue] ?? nil, "https://cdn/tv.png")
    }

    /// A single-platform app must NOT trigger a builds fetch (its per-platform icon
    /// equals the app icon anyway), and its per-platform version's icon stays nil.
    func testSinglePlatformAppSkipsBuildsFetchAndLeavesPerPlatformIconNil() async throws {
        let account = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.apps = [
            StackProtocols.AppInfo(id: "app-1", name: "Single", bundleId: "com.single", platform: nil)
        ]
        // Two versions, same platform → single distinct platform.
        connection.versions = [
            "app-1": [
                makePlatformVersion(id: "v-ios-1", appId: "app-1", platform: .ios, state: .readyForSale, createdOffset: 0),
                makePlatformVersion(id: "v-ios-2", appId: "app-1", platform: .ios, state: .prepareForSubmission, createdOffset: -100)
            ]
        ]
        // Builds exist but must never be fetched for a single-platform app.
        connection.builds = [
            "app-1": [makeBuild(id: "b-ios", platform: .ios, iconUrl: "https://cdn/ios.png")]
        ]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        XCTAssertFalse(connection.fetchedBuildsForAppIds.contains("app-1"),
                       "Single-platform apps must not trigger a builds fetch")

        let saved: AppModel? = try await mockStorage.fetch(AppModel.self, id: "\(account.id).app-1")
        XCTAssertEqual(saved?.platformVersions?.count, 1, "One iOS platform version (deduped)")
        XCTAssertNil(saved?.platformVersions?.first?.iconUrl)
    }

    // MARK: - Per-app export scope (#93)

    func testSyncPersistsOnlyAppsAllowedByScope() async throws {
        let account = AccountModel(
            name: "Scoped",
            providerType: .apple,
            origin: .imported,
            appsBundles: ["com.a", "com.c"]
        )
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.apps = [
            StackProtocols.AppInfo(id: "a", name: "A", bundleId: "com.a", platform: nil),
            StackProtocols.AppInfo(id: "b", name: "B", bundleId: "com.b", platform: nil),
            StackProtocols.AppInfo(id: "c", name: "C", bundleId: "com.c", platform: nil)
        ]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let savedA: AppModel? = try await mockStorage.fetch(AppModel.self, id: "\(account.id).a")
        let savedB: AppModel? = try await mockStorage.fetch(AppModel.self, id: "\(account.id).b")
        let savedC: AppModel? = try await mockStorage.fetch(AppModel.self, id: "\(account.id).c")

        XCTAssertNotNil(savedA)
        XCTAssertNil(savedB, "App outside the scope must not be persisted")
        XCTAssertNotNil(savedC)

        let metadata: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(account.id)"
        )
        XCTAssertEqual(metadata?.appsSynced, 2)
    }

    func testSyncNilScopePersistsAllApps() async throws {
        let account = AccountModel(name: "Unrestricted", providerType: .apple, appsBundles: nil)
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.apps = [
            StackProtocols.AppInfo(id: "a", name: "A", bundleId: "com.a", platform: nil),
            StackProtocols.AppInfo(id: "b", name: "B", bundleId: "com.b", platform: nil),
            StackProtocols.AppInfo(id: "c", name: "C", bundleId: "com.c", platform: nil)
        ]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let metadata: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(account.id)"
        )
        XCTAssertEqual(metadata?.appsSynced, 3)
    }

    func testSyncEmptyScopePersistsAllApps() async throws {
        let account = AccountModel(name: "EmptyScope", providerType: .apple, appsBundles: [])
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        let connection = MockAppleAccountSyncing()
        connection.apps = [
            StackProtocols.AppInfo(id: "a", name: "A", bundleId: "com.a", platform: nil),
            StackProtocols.AppInfo(id: "b", name: "B", bundleId: "com.b", platform: nil)
        ]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let metadata: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(account.id)"
        )
        XCTAssertEqual(metadata?.appsSynced, 2)
    }

    /// Purge: a previously cached app now outside the scope must be deleted on sync.
    func testSyncPurgesCachedAppExcludedByScope() async throws {
        let account = AccountModel(
            name: "Scoped",
            providerType: .apple,
            origin: .imported,
            appsBundles: ["com.a", "com.c"]
        )
        try await mockStorage.save(account, id: account.id)
        setCredentials(issuerID: "issuer-1", for: account)

        // Pre-seed excluded app "b" as if a prior, unrestricted sync had persisted it.
        let cachedB = AppModel(id: "b", name: "B", bundleId: "com.b", accountId: account.id)
        try await mockStorage.save(cachedB, id: "\(account.id).b")

        let connection = MockAppleAccountSyncing()
        connection.apps = [
            StackProtocols.AppInfo(id: "a", name: "A", bundleId: "com.a", platform: nil),
            StackProtocols.AppInfo(id: "b", name: "B", bundleId: "com.b", platform: nil),
            StackProtocols.AppInfo(id: "c", name: "C", bundleId: "com.c", platform: nil)
        ]
        connections["issuer-1"] = connection

        await sut.syncAll().value

        let savedB: AppModel? = try await mockStorage.fetch(AppModel.self, id: "\(account.id).b")
        XCTAssertNil(savedB, "Excluded app must be purged from the cache")
    }

    // MARK: - Helpers

    private func makePlatformVersion(
        id: String,
        appId: String,
        platform: AppPlatform,
        state: AppStoreState,
        createdOffset: TimeInterval
    ) -> AppStoreVersionModel {
        AppStoreVersionModel(
            id: id,
            platform: platform,
            appStoreState: state,
            versionString: "1.0-\(platform.rawValue)",
            createdDate: Date(timeIntervalSinceReferenceDate: 1_000_000 + createdOffset),
            appId: appId
        )
    }

    private func makeBuild(id: String, platform: AppPlatform, iconUrl: String?) -> BuildModel {
        BuildModel(id: id, iconUrl: iconUrl, platform: platform.rawValue)
    }

    private func makeAgreementError() -> Error {
        StackCoreRust.StackError.PendingAgreements(message: "You must accept the latest agreements.")
    }

    private func makeError(status: Int, code: String, detail: String?) -> Error {
        let body = "{\"errors\":[{\"status\":\"\(status)\",\"code\":\"\(code)\",\"title\":\"\",\"detail\":\"\(detail ?? "")\"}]}"
        return StackCoreRust.StackError.Http(status: UInt16(status), message: body)
    }

    private func setCredentials(issuerID: String, for account: AccountModel) {
        let creds = AppleCredentials(
            issuerID: issuerID,
            privateKeyID: "key-\(issuerID)",
            privateKey: "pk"
        )
        mockKeychain.setObject(creds, forKey: "credentials.\(account.id)")
    }

    private func makeVersion(
        id: String,
        appId: String,
        state: AppStoreState,
        versionString: String
    ) -> AppStoreVersionModel {
        AppStoreVersionModel(
            id: id,
            platform: nil,
            appStoreState: state,
            versionString: versionString,
            appId: appId
        )
    }

    // MARK: - Analytics (`sync` action)

    func testEachRunIsTrackedOnceWithTriggerAndScreen() async {
        let first = sut.syncAll(trigger: .manual, screen: .allReviews)
        let coalesced = sut.syncAll(trigger: .foreground, screen: .home)
        await first.value
        await coalesced.value

        let events = analytics.actions(of: .sync)
        XCTAssertEqual(events.count, 1, "A coalesced call is not a second run")
        XCTAssertEqual(events.first?.parameters["trigger"], .string("manual"))
        XCTAssertEqual(events.first?.parameters["screen_name"], .string("all_reviews"))
        XCTAssertEqual(events.first?.parameters["result"], .string("success"))
        XCTAssertEqual(events.first?.parameters["count"], .int(0))
        XCTAssertNotNil(events.first?.parameters["duration_bucket"])
    }

    func testBackgroundRunIsTrackedWithoutAScreen() async {
        await sut.syncAll(mode: .lightweight, trigger: .background, screen: nil).value

        let event = analytics.actions(of: .sync).first
        XCTAssertEqual(event?.parameters["trigger"], .string("background"))
        XCTAssertNil(event?.parameters["screen_name"])
    }

    func testLightweightRunDefaultsToTheBackgroundTrigger() async {
        await sut.syncAll(mode: .lightweight).value

        XCTAssertEqual(analytics.actions(of: .sync).first?.parameters["trigger"], .string("background"))
    }

    func testFailedLegIsTrackedWithItsCategory() async throws {
        // An Apple account without credentials fails its leg.
        let account = AccountModel(name: "No Keys", providerType: .apple)
        try await mockStorage.save(account, id: account.id)

        await sut.syncAll().value

        let event = try XCTUnwrap(analytics.actions(of: .sync).first)
        XCTAssertEqual(event.parameters["result"], .string("failure"))
        XCTAssertEqual(event.parameters["failed_count"], .int(1))
        XCTAssertEqual(event.parameters["count"], .int(1))
        XCTAssertEqual(event.parameters["error_category"], .string("invalid_credentials"))
        XCTAssertEqual(event.parameters["trigger"], .string("foreground"))
    }

    func testSyncEventDurationBuckets() {
        let outcome = StackConnect.SyncService.RunOutcome(accountCount: 2)
        let buckets = [Duration.seconds(1), .seconds(5), .seconds(29), .seconds(45), .seconds(120)].map {
            StackConnect.SyncService.syncEvent(outcome, trigger: .foreground, screen: .home, duration: $0)
                .parameters["duration_bucket"]
        }
        XCTAssertEqual(buckets, ["under_5s", "5_15s", "15_30s", "30_60s", "over_60s"].map { AnalyticsValue.string($0) })
    }

    func testDominantFailureCategoryIsTheMostFrequentThenByName() {
        let change = SyncChange.failed(accountId: "a", category: .network)
            + SyncChange.failed(accountId: "b", category: .server)
            + SyncChange.failed(accountId: "c", category: .server)
        XCTAssertEqual(change.dominantFailureCategory, .server)

        let tie = SyncChange.failed(accountId: "a", category: .server) + SyncChange.failed(accountId: "b", category: .network)
        XCTAssertEqual(tie.dominantFailureCategory, .network, "Ties resolve alphabetically, deterministically")
        XCTAssertNil(SyncChange().dominantFailureCategory)
    }
}
