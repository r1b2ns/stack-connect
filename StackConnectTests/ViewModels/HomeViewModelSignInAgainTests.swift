import XCTest
import StackProtocols
@testable import StackConnect

/// The Home "sign in again" banner: which accounts' personal sign-ins expired
/// (Apple ID session, Google login), the in-memory close, the auto-hide and
/// the re-authentication it starts.
@MainActor
final class HomeViewModelSignInAgainTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var appleStatus: MockAppleSessionStatus!
    private var googleStatus: MockGoogleLoginStatus!
    private var googleAuth: MockGoogleAuthService!
    private var analytics: MockAnalyticsTracker!
    private var center: NotificationCenter!
    private var now: Date!

    private let appleId = "dev@example.com"

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        appleStatus = MockAppleSessionStatus()
        googleStatus = MockGoogleLoginStatus()
        googleAuth = MockGoogleAuthService()
        analytics = MockAnalyticsTracker()
        center = NotificationCenter()
        now = Date(timeIntervalSince1970: 1_000_000)
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        appleStatus = nil
        googleStatus = nil
        googleAuth = nil
        analytics = nil
        center = nil
        now = nil
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
            signInExpiry: ExpiredSignInResolver(
                keychain: keychain,
                appleStatus: appleStatus,
                googleStatus: googleStatus,
                now: { [unowned self] in self.now }
            ),
            googleAuth: googleAuth,
            notificationCenter: center
        )
    }

    // MARK: - Fixtures

    @discardableResult
    private func addAppleSessionAccount(_ name: String, team: UInt64, appleId: String? = nil) async throws -> AccountModel {
        let account = AccountModel(name: name, providerType: .apple, authMethod: .appleIdSignIn)
        try await storage.save(account, id: account.id)
        keychain.setObject(
            AppleCredentials(webSession: .init(appleId: appleId ?? self.appleId, teamId: team, teamName: name)),
            forKey: "credentials.\(account.id)"
        )
        return account
    }

    @discardableResult
    private func addGoogleAccount(
        _ name: String,
        provider: ProviderType = .googlePlay,
        loginId: String = "user-1",
        storeGrant: Bool = true,
        refreshTokenExpiresAt: Date? = nil
    ) async throws -> AccountModel {
        let account = AccountModel(name: name, providerType: provider, authMethod: .googleSignIn)
        try await storage.save(account, id: account.id)
        if provider == .firebase {
            keychain.setObject(FirebaseCredentials(googleLoginId: loginId), forKey: "credentials.\(account.id)")
        } else {
            keychain.setObject(GooglePlayCredentials(googleLoginId: loginId), forKey: "credentials.\(account.id)")
        }
        if storeGrant {
            var grant = GoogleAuthFixtures.grant(loginId: loginId, email: "\(loginId)@example.com")
            grant.refreshTokenExpiresAt = refreshTokenExpiresAt
            GoogleLoginKeychainStore(keychain: keychain).save(grant)
        }
        return account
    }

    @discardableResult
    private func addKeyFileAccount(_ name: String) async throws -> AccountModel {
        let account = AccountModel(name: name, providerType: .apple)
        try await storage.save(account, id: account.id)
        return account
    }

    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "condition not met in time", file: file, line: line)
    }

    // MARK: - Expired detection

    func testNoBannerWhenEverySignInWorks() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        try await addGoogleAccount("Play")
        try await addKeyFileAccount("API Key")
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertTrue(sut.uiState.expiredSignIns.isEmpty)
        XCTAssertFalse(sut.uiState.showSignInAgainBanner)
    }

    func testExpiredAppleIdSessionGroupsItsTeamAccounts() async throws {
        let teamA = try await addAppleSessionAccount("Team A", team: 1)
        let teamB = try await addAppleSessionAccount("Team B", team: 2)
        try await addAppleSessionAccount("Other", team: 3, appleId: "other@example.com")
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertEqual(sut.uiState.expiredSignIns.count, 1)
        let signIn = try XCTUnwrap(sut.uiState.expiredSignIns.first)
        XCTAssertEqual(signIn.provider, .appleId(appleId))
        XCTAssertEqual(signIn.login, appleId)
        XCTAssertEqual(signIn.accounts.map(\.id), [teamA.id, teamB.id])
        XCTAssertEqual(sut.uiState.expiredAccountCount, 2)
        XCTAssertTrue(sut.uiState.showSignInAgainBanner)
    }

    func testGoogleLoginMarkedExpiredIsListedWithItsEmail() async throws {
        let play = try await addGoogleAccount("Play", provider: .googlePlay)
        let firebase = try await addGoogleAccount("Firebase", provider: .firebase)
        googleStatus.markExpired(loginId: "user-1")
        let sut = makeSUT()

        await sut.loadDashboard()

        let signIn = try XCTUnwrap(sut.uiState.expiredSignIns.first)
        XCTAssertEqual(sut.uiState.expiredSignIns.count, 1)
        XCTAssertEqual(signIn.provider, .google(loginId: "user-1"))
        XCTAssertEqual(signIn.login, "user-1@example.com")
        XCTAssertEqual(Set(signIn.accounts.map(\.id)), [play.id, firebase.id])
    }

    func testGoogleLoginWithoutAGrantOnTheDeviceIsExpired() async throws {
        try await addGoogleAccount("Play", storeGrant: false)
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertEqual(sut.uiState.expiredSignIns.map(\.provider), [.google(loginId: "user-1")])
        XCTAssertNil(sut.uiState.expiredSignIns.first?.login, "no grant, no e-mail")
    }

    func testGoogleLoginPastItsRefreshTokenExpiryIsExpired() async throws {
        try await addGoogleAccount("Expired", loginId: "user-1", refreshTokenExpiresAt: now.addingTimeInterval(-1))
        try await addGoogleAccount("Valid", loginId: "user-2", refreshTokenExpiresAt: now.addingTimeInterval(3600))
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertEqual(sut.uiState.expiredSignIns.map(\.provider), [.google(loginId: "user-1")])
    }

    func testSeveralSignInsAreListedSeparately() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        try await addGoogleAccount("Play")
        appleStatus.markExpired(appleId: appleId)
        googleStatus.markExpired(loginId: "user-1")
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertEqual(sut.uiState.expiredSignIns.count, 2)
        XCTAssertEqual(sut.uiState.expiredAccountCount, 2)
    }

    func testRefreshReReadsTheExpiredSignIns() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        let sut = makeSUT()
        await sut.loadDashboard()
        XCTAssertFalse(sut.uiState.showSignInAgainBanner)

        appleStatus.markExpired(appleId: appleId)
        await sut.reloadExpiredSignIns()

        XCTAssertTrue(sut.uiState.showSignInAgainBanner)
    }

    func testStatusChangeNotificationUpdatesTheBanner() async throws {
        try await addGoogleAccount("Play")
        let sut = makeSUT()
        await sut.loadDashboard()
        XCTAssertFalse(sut.uiState.showSignInAgainBanner)

        googleStatus.markExpired(loginId: "user-1")
        center.post(name: .signInStatusDidChange, object: nil)

        await waitUntil { sut.uiState.showSignInAgainBanner }
    }

    // MARK: - Auto-hide

    func testBannerHidesOnceNoExpiredSignInRemains() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        await sut.loadDashboard()
        XCTAssertTrue(sut.uiState.showSignInAgainBanner)

        appleStatus.markValid(appleId: appleId)
        center.post(name: .signInStatusDidChange, object: nil)

        await waitUntil { !sut.uiState.showSignInAgainBanner }
        XCTAssertTrue(sut.uiState.expiredSignIns.isEmpty)
    }

    func testChooseSheetClosesWhenTheLastSignInRecovers() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        try await addGoogleAccount("Play")
        appleStatus.markExpired(appleId: appleId)
        googleStatus.markExpired(loginId: "user-1")
        let sut = makeSUT()
        await sut.loadDashboard()
        await sut.startSignInAgain()
        XCTAssertEqual(sut.uiState.signInAgainSheet, .choose)

        appleStatus.markValid(appleId: appleId)
        googleStatus.markValid(loginId: "user-1")
        await sut.reloadExpiredSignIns()

        XCTAssertNil(sut.uiState.signInAgainSheet)
    }

    // MARK: - Dismissal

    func testCloseHidesTheBannerAndTracksIt() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        await sut.loadDashboard()

        sut.dismissSignInAgainBanner()

        XCTAssertFalse(sut.uiState.showSignInAgainBanner)
        XCTAssertEqual(sut.uiState.expiredSignIns.count, 1, "still expired, only hidden")
        XCTAssertEqual(analytics.taps(of: .dismissSignInAgainBanner), [.buttonTap(.dismissSignInAgainBanner, on: .home)])
    }

    func testClosedBannerStaysHiddenOnReloadAndRefresh() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        await sut.loadDashboard()
        sut.dismissSignInAgainBanner()

        await sut.loadDashboard()
        await sut.reloadExpiredSignIns()

        XCTAssertFalse(sut.uiState.showSignInAgainBanner)
    }

    func testClosedBannerIsBackWithANewViewModel() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let first = makeSUT()
        await first.loadDashboard()
        first.dismissSignInAgainBanner()

        // A new launch builds a new HomeViewModel: the close isn't persisted.
        let relaunched = makeSUT()
        await relaunched.loadDashboard()

        XCTAssertTrue(relaunched.uiState.showSignInAgainBanner)
    }

    func testANewlyExpiredAccountShowsTheClosedBannerAgain() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        try await addGoogleAccount("Play")
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        await sut.loadDashboard()
        sut.dismissSignInAgainBanner()

        googleStatus.markExpired(loginId: "user-1")
        await sut.reloadExpiredSignIns()

        XCTAssertTrue(sut.uiState.showSignInAgainBanner)
        XCTAssertEqual(sut.uiState.expiredSignIns.count, 2)
    }

    func testAnAccountThatRecoversAndExpiresAgainShowsTheBannerAgain() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        await sut.loadDashboard()
        sut.dismissSignInAgainBanner()

        appleStatus.markValid(appleId: appleId)
        await sut.reloadExpiredSignIns()
        appleStatus.markExpired(appleId: appleId)
        await sut.reloadExpiredSignIns()

        XCTAssertTrue(sut.uiState.showSignInAgainBanner)
    }

    // MARK: - Sign in again

    func testOneExpiredAppleIdOpensItsSignInDirectly() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        await sut.loadDashboard()

        await sut.startSignInAgain()

        XCTAssertEqual(sut.uiState.signInAgainSheet, .apple(appleId: appleId))
        XCTAssertEqual(analytics.taps(of: .signInAgain), [.buttonTap(.signInAgain, on: .home)])
    }

    func testFinishedAppleSignInClosesTheSheet() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        await sut.loadDashboard()
        await sut.startSignInAgain()

        appleStatus.markValid(appleId: appleId)
        sut.appleSignInAgainFinished()

        XCTAssertNil(sut.uiState.signInAgainSheet)
        await waitUntil { !sut.uiState.showSignInAgainBanner }
    }

    func testSeveralSignInsOpenTheListAndAnAppleRowPushesItsSignIn() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        try await addGoogleAccount("Play")
        appleStatus.markExpired(appleId: appleId)
        googleStatus.markExpired(loginId: "user-1")
        let sut = makeSUT()
        await sut.loadDashboard()

        await sut.startSignInAgain()

        XCTAssertEqual(sut.uiState.signInAgainSheet, .choose)
        XCTAssertEqual(analytics.taps(of: .chooseSignInAgain), [.buttonTap(.chooseSignInAgain, on: .home)])

        await sut.signInAgain("apple:\(appleId)")

        XCTAssertEqual(sut.uiState.signInAgainSheet, .choose, "the sign-in is pushed inside the list")
        XCTAssertEqual(sut.uiState.appleSignInAgainId, appleId)

        appleStatus.markValid(appleId: appleId)
        sut.appleSignInAgainFinished()

        XCTAssertEqual(sut.uiState.signInAgainSheet, .choose, "the Google sign-in is still left")
        XCTAssertNil(sut.uiState.appleSignInAgainId)
    }

    func testOneExpiredGoogleLoginSignsInAgainWithTheSameUser() async throws {
        try await addGoogleAccount("Play")
        googleStatus.markExpired(loginId: "user-1")
        googleAuth.reauthenticateResult = .success(MockGoogleAuthService.result(loginId: "user-1", isNewLogin: false))
        let sut = makeSUT()
        await sut.loadDashboard()
        // What `GoogleAuthService` records once Google's page succeeds.
        googleStatus.markValid(loginId: "user-1")

        await sut.startSignInAgain()

        XCTAssertEqual(googleAuth.reauthenticateCalls, ["user-1"])
        XCTAssertNil(sut.uiState.signInAgainSheet, "Google's own page, no sheet")
        XCTAssertTrue(sut.uiState.workingSignInIds.isEmpty)
        XCTAssertFalse(sut.uiState.showSignInAgainBanner)
        XCTAssertEqual(analytics.taps(of: .signInAgain), [.buttonTap(.signInAgain, on: .home)])
        XCTAssertEqual(analytics.actions(of: .googleSignIn).count, 1)
    }

    func testFailedGoogleSignInKeepsTheBannerWithFeedback() async throws {
        try await addGoogleAccount("Play")
        googleStatus.markExpired(loginId: "user-1")
        googleAuth.reauthenticateResult = .failure(GoogleAuthError.differentAccount(expectedEmail: "user-1@example.com"))
        let sut = makeSUT()
        await sut.loadDashboard()

        await sut.startSignInAgain()

        XCTAssertTrue(sut.uiState.showSignInAgainBanner)
        XCTAssertNotNil(sut.uiState.signInAgainFeedback["google:user-1"])
        XCTAssertTrue(sut.uiState.workingSignInIds.isEmpty)
    }

    func testCancelledGoogleSignInShowsNoFeedback() async throws {
        try await addGoogleAccount("Play")
        googleStatus.markExpired(loginId: "user-1")
        googleAuth.reauthenticateResult = .failure(GoogleAuthError.cancelled)
        let sut = makeSUT()
        await sut.loadDashboard()

        await sut.startSignInAgain()

        XCTAssertTrue(sut.uiState.signInAgainFeedback.isEmpty)
        XCTAssertTrue(sut.uiState.showSignInAgainBanner)
    }

    func testCloseSheetClearsIt() async throws {
        try await addAppleSessionAccount("Team A", team: 1)
        appleStatus.markExpired(appleId: appleId)
        let sut = makeSUT()
        await sut.loadDashboard()
        await sut.startSignInAgain()

        sut.closeSignInAgainSheet()

        XCTAssertNil(sut.uiState.signInAgainSheet)
        XCTAssertTrue(sut.uiState.showSignInAgainBanner, "closing the sheet doesn't close the banner")
    }
}
