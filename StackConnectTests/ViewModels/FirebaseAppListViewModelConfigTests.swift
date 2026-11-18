import XCTest
@testable import StackConnect

/// `fetchConfig` of the Firebase app detail: the config row must always leave
/// the loading state — with the file on success, with an error on failure.
/// Requests go through the real `APIProviderFirebase` wired to the in-process
/// fake Firebase server.
@MainActor
final class FirebaseAppListViewModelConfigTests: XCTestCase {

    private var previousProviders: (any FirebaseProviderMaking)!
    private var keys: MockKeyStorable!

    private let account = AccountModel(id: FakeDataSeeder.AccountID.northwindFirebase, name: "Northwind Labs", providerType: .firebase)
    private let project = FirebaseProjectModel(id: "trailhead-prod-4f2a1", displayName: "Trailhead", projectId: "trailhead-prod-4f2a1")

    override func setUp() async throws {
        try await super.setUp()
        previousProviders = BackendEnvironment.firebaseProviders
        let clock = FakeClock(now: Date(timeIntervalSince1970: 1_790_000_000))
        BackendEnvironment.firebaseProviders = FakeFirebaseProviderFactory(server: FakeFirebaseServer(clock: clock))
        keys = MockKeyStorable()
        FakeDataSeeder.writeCredentials(into: keys)
    }

    override func tearDown() async throws {
        BackendEnvironment.firebaseProviders = previousProviders
        previousProviders = nil
        keys = nil
        try await super.tearDown()
    }

    private func makeSUT(keychain: KeyStorable? = nil) -> FirebaseAppListViewModel {
        FirebaseAppListViewModel(account: account, project: project, keychain: keychain ?? keys, analytics: MockAnalyticsTracker())
    }

    private func app(_ appId: String, platform: FirebaseAppPlatform) -> FirebaseAppModel {
        FirebaseAppModel(id: appId, displayName: "App", appId: appId, platform: platform)
    }

    func testFetchConfigLoadsThePlistForAnIosApp() async throws {
        let sut = makeSUT()

        await sut.fetchConfig(app("1:483920175624:ios:8c1b2f3a4d5e6f70", platform: .ios))

        XCTAssertNil(sut.uiState.configError)
        XCTAssertEqual(sut.uiState.configFilename, "GoogleService-Info.plist")
        let content = try XCTUnwrap(sut.uiState.configContent)
        XCTAssertTrue(content.contains("<key>GOOGLE_APP_ID</key>"))
        XCTAssertTrue(content.contains("1:483920175624:ios:8c1b2f3a4d5e6f70"))
    }

    func testFetchConfigLoadsGoogleServicesJSONForAnAndroidApp() async throws {
        let sut = makeSUT()

        await sut.fetchConfig(app("1:483920175624:android:3e9d7c1b5a2f4e60", platform: .android))

        XCTAssertNil(sut.uiState.configError)
        XCTAssertEqual(sut.uiState.configFilename, "google-services.json")
        XCTAssertTrue(try XCTUnwrap(sut.uiState.configContent).contains("\"mobilesdk_app_id\""))
    }

    func testFetchConfigBuildsTheWebConfig() async throws {
        let sut = makeSUT()

        await sut.fetchConfig(app("1:483920175624:web:b7e1d4c9a2f05e31", platform: .web))

        XCTAssertNil(sut.uiState.configError)
        XCTAssertEqual(sut.uiState.configFilename, "firebase-config.json")
        XCTAssertTrue(try XCTUnwrap(sut.uiState.configContent).contains("\"appId\": \"1:483920175624:web:b7e1d4c9a2f05e31\""))
    }

    func testFetchConfigFailureSetsAnErrorInsteadOfLoadingForever() async {
        let sut = makeSUT()

        await sut.fetchConfig(app("1:483920175624:ios:doesnotexist", platform: .ios))

        XCTAssertNil(sut.uiState.configContent)
        XCTAssertNil(sut.uiState.configFilename)
        XCTAssertEqual(sut.uiState.configError, String(localized: "Couldn't load the configuration file."))
        XCTAssertNil(sut.uiState.toastMessage)
    }

    func testFetchConfigWithoutCredentialsSetsAnError() async {
        let sut = makeSUT(keychain: MockKeyStorable())

        await sut.fetchConfig(app("1:483920175624:ios:8c1b2f3a4d5e6f70", platform: .ios))

        XCTAssertNil(sut.uiState.configContent)
        XCTAssertEqual(sut.uiState.configError, String(localized: "No credentials found for this account."))
    }

    func testRetryAfterFailureClearsTheError() async {
        let sut = makeSUT()
        await sut.fetchConfig(app("1:483920175624:ios:doesnotexist", platform: .ios))
        XCTAssertNotNil(sut.uiState.configError)

        await sut.fetchConfig(app("1:483920175624:ios:8c1b2f3a4d5e6f70", platform: .ios))

        XCTAssertNil(sut.uiState.configError)
        XCTAssertNotNil(sut.uiState.configContent)
    }

    func testAndroidUsesTheAndroidGlyphAsset() {
        XCTAssertEqual(FirebaseAppPlatform.android.glyph, .android)
        XCTAssertEqual(FirebaseAppPlatform.ios.glyph, .system("apple.logo"))
    }
}
