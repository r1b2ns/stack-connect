import XCTest
import StackProtocols
@testable import StackConnect

/// The Home side of the automatic Apple ID sign-in: no banner while it runs,
/// "Confirm your Apple account" while its code waits, and the toasts.
@MainActor
final class HomeViewModelAutoReauthTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var appleStatus: MockAppleSessionStatus!
    private var analytics: MockAnalyticsTracker!
    private var center: NotificationCenter!
    private var autoReauth: MockAppleSessionAutoReauthenticator!

    private let appleId = "dev@example.com"
    private var signInId: String { ExpiredSignIn.id(of: .appleId(appleId)) }

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        appleStatus = MockAppleSessionStatus()
        analytics = MockAnalyticsTracker()
        center = NotificationCenter()
        autoReauth = MockAppleSessionAutoReauthenticator()
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        appleStatus = nil
        analytics = nil
        center = nil
        autoReauth = nil
        try await super.tearDown()
    }

    private func makeSUT() -> HomeViewModel {
        HomeViewModel(
            storage: storage,
            keychain: keychain,
            preferences: MockKeyStorable(),
            syncService: SyncService(storage: MockPersistentStorable(), keychain: MockKeyStorable(), analytics: MockAnalyticsTracker()),
            teamUsersFetcherFactory: { _ in nil },
            analytics: analytics,
            featureFlags: .googlePlayOn,
            signInExpiry: ExpiredSignInResolver(keychain: keychain, appleStatus: appleStatus, googleStatus: MockGoogleLoginStatus()),
            googleAuth: MockGoogleAuthService(),
            notificationCenter: center,
            autoReauth: autoReauth
        )
    }

    @discardableResult
    private func addAppleSessionAccount(_ name: String, team: UInt64) async throws -> AccountModel {
        let account = AccountModel(name: name, providerType: .apple, authMethod: .appleIdSignIn)
        try await storage.save(account, id: account.id)
        keychain.setObject(
            AppleCredentials(webSession: .init(appleId: appleId, teamId: team, teamName: name)),
            forKey: "credentials.\(account.id)"
        )
        return account
    }

    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "condition not met in time", file: file, line: line)
    }

    // MARK: - Banner

    func testNoBannerWhileReconnecting() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        autoReauth.states[appleId] = .reconnecting
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertTrue(sut.uiState.expiredSignIns.isEmpty, "its chips say Reconnecting… instead")
        XCTAssertFalse(sut.uiState.showSignInAgainBanner)
    }

    func testAwaitingCodeSwitchesTheBannerCopy() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        autoReauth.states[appleId] = .awaitingCode(.trustedDevices)
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertTrue(sut.uiState.showSignInAgainBanner)
        XCTAssertEqual(sut.uiState.awaitingCodeSignIns, [signInId: .trustedDevices])
        XCTAssertEqual(HomeSignInAgainCopy.awaitingCodeTitle, String(localized: "Confirm your Apple account"))
        XCTAssertEqual(HomeSignInAgainCopy.enterCode, String(localized: "Enter Code"))
        XCTAssertEqual(HomeSignInAgainCopy.awaitingCodeMessage(.trustedDevices), String(localized: "Apple sent a code to your devices."))
        XCTAssertEqual(HomeSignInAgainCopy.awaitingCodeMessage(.phone), String(localized: "Apple sent a code to your phone."))
        XCTAssertEqual(HomeSignInAgainCopy.awaitingCodeMessage(.notSent), String(localized: "Apple needs a code to confirm it's you."))
    }

    func testManualBannerWithoutAnAutomaticSignIn() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertTrue(sut.uiState.showSignInAgainBanner)
        XCTAssertTrue(sut.uiState.awaitingCodeSignIns.isEmpty)
    }

    func testEnterCodeOpensTheSignInSheetAndTracksIt() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        autoReauth.states[appleId] = .awaitingCode(.trustedDevices)
        let sut = makeSUT()
        await sut.loadDashboard()

        await sut.startSignInAgain()

        XCTAssertEqual(sut.uiState.signInAgainSheet, .apple(appleId: appleId), "the sheet resumes the code step")
        XCTAssertEqual(analytics.taps(of: .enterCode), [.buttonTap(.enterCode, on: .home)])
        XCTAssertTrue(analytics.taps(of: .signInAgain).isEmpty)
    }

    func testACodeShowsTheClosedBannerAgain() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        await sut.loadDashboard()
        sut.dismissSignInAgainBanner()

        autoReauth.states[appleId] = .awaitingCode(.trustedDevices)
        autoReauth.send(.finished(appleId: appleId, outcome: .needsCode))

        await waitUntil { sut.uiState.showSignInAgainBanner }
        XCTAssertEqual(sut.uiState.awaitingCodeSignIns, [signInId: .trustedDevices])
    }

    // MARK: - Toasts

    func testToastsWhileReconnectingAndOnceReconnected() async throws {
        let sut = makeSUT()

        autoReauth.send(.started(appleId: appleId))
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Reconnecting Apple account…"))

        autoReauth.send(.finished(appleId: appleId, outcome: .done))
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Apple account reconnected"))
    }

    func testAFailedAttemptClearsTheToast() {
        let sut = makeSUT()

        autoReauth.send(.started(appleId: appleId))
        autoReauth.send(.finished(appleId: appleId, outcome: .failed))

        XCTAssertNil(sut.uiState.toastMessage)
    }
}
