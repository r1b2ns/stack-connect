import XCTest
import StackProtocols
@testable import StackConnect

/// What an account added with "Sign in with Apple ID" can't do (plan G3, D7)
/// and the `appleIdSignIn` flag in Add Account (D6).
@MainActor
final class AppleSessionGatingTests: XCTestCase {

    private let session = AccountModel(name: "Session", providerType: .apple, authMethod: .appleIdSignIn)
    private let apiKey = AccountModel(name: "Key", providerType: .apple)
    private let bundle = BundleIdentifierModel(id: "B1", identifier: "com.example.app", name: "App", platform: "IOS", seedId: nil)

    // MARK: - Account capabilities

    func testSessionAccountsAreNotExportableAndSayWhy() {
        XCTAssertFalse(session.isExportable)
        XCTAssertNotNil(session.exportUnavailableReason)
        XCTAssertTrue(apiKey.isExportable)
        XCTAssertNil(apiKey.exportUnavailableReason)
        XCTAssertNil(AccountModel(name: "G", providerType: .googlePlay, authMethod: .googleSignIn).exportUnavailableReason,
                     "Google sign-in keeps hiding the export as before")
    }

    func testSessionExportPayloadIsRefused() {
        let keychain = MockKeyStorable()
        keychain.setObject(AppleCredentials(webSession: .init(appleId: "a@b.c", teamId: 1, teamName: "T")), forKey: "credentials.\(session.id)")

        XCTAssertNil(AccountTransferCredentials.exportPayload(for: session, keychain: keychain))
    }

    func testSessionAccountsHaveNoAnalyticsReportsNorBundleIdRenameOrDelete() {
        XCTAssertTrue(session.isAppleIdSession)
        XCTAssertFalse(session.supportsAnalyticsReports)
        XCTAssertFalse(session.supportsBundleIdRenameAndDelete)
        XCTAssertTrue(apiKey.supportsAnalyticsReports)
        XCTAssertTrue(apiKey.supportsBundleIdRenameAndDelete)
    }

    func testAnalyticsReportsRoutesAreRefusedForSessionAccounts() {
        var routes: [HomeRoute] = []
        let coordinator = HomeCoordinator(routeHandler: { routes.append($0) })
        let report = AnalyticsCatalogReport(displayName: "Downloads", subtitle: "", apiName: "App Store Downloads", category: .appStoreCommerce)

        coordinator.navigateToAnalyticsReports(appId: "1", appName: "App", account: session)
        coordinator.navigateToAnalyticsReportDetail(appId: "1", appName: "App", report: report, account: session)
        coordinator.navigateToAnalyticsReportFiles(appId: "1", appName: "App", report: report, account: session)
        XCTAssertTrue(routes.isEmpty)

        coordinator.navigateToAnalyticsReports(appId: "1", appName: "App", account: apiKey)
        coordinator.navigateToAnalyticsReportDetail(appId: "1", appName: "App", report: report, account: apiKey)
        coordinator.navigateToAnalyticsReportFiles(appId: "1", appName: "App", report: report, account: apiKey)
        XCTAssertEqual(routes.count, 3)
    }

    func testBundleIdRenameAndDeleteAreRefusedForSessionAccounts() async {
        let keychain = MockKeyStorable()
        keychain.setObject(AppleCredentials(webSession: .init(appleId: "a@b.c", teamId: 1, teamName: "T")), forKey: "credentials.\(session.id)")
        let sut = IdentifierDetailViewModel(account: session, bundleId: bundle, keychain: keychain, analytics: MockAnalyticsTracker())

        XCTAssertFalse(sut.uiState.canRenameOrDelete)
        XCTAssertNotNil(sut.uiState.renameOrDeleteUnavailableReason)
        let renamed = await sut.rename(to: "New")
        let deleted = await sut.delete()

        XCTAssertFalse(renamed)
        XCTAssertFalse(deleted)
        XCTAssertNil(sut.uiState.errorMessage, "refused before any request")
        XCTAssertEqual(sut.uiState.bundleId.name, "App")
    }

    func testApiKeyAccountsKeepBundleIdRenameAndDelete() {
        let sut = IdentifierDetailViewModel(account: apiKey, bundleId: bundle, keychain: MockKeyStorable(), analytics: MockAnalyticsTracker())

        XCTAssertTrue(sut.uiState.canRenameOrDelete)
        XCTAssertNil(sut.uiState.renameOrDeleteUnavailableReason)
    }

    // MARK: - Flag in Add Account

    private func makeAddAccount(_ provider: ProviderType, flag: Bool?, analytics: MockAnalyticsTracker = MockAnalyticsTracker()) -> (AddAccountViewModel, () -> Void) {
        let suite = "AppleSessionGatingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        if let flag { defaults.set(flag, forKey: FeatureFlag.appleIdSignIn.rawValue) }
        let sut = AddAccountViewModel(
            providerType: provider,
            storage: MockPersistentStorable(),
            keychain: MockKeyStorable(),
            analytics: analytics,
            featureFlags: FeatureFlags(defaults: defaults),
            googleAuth: MockGoogleAuthService()
        )
        return (sut, { defaults.removePersistentDomain(forName: suite) })
    }

    func testFlagOnOffersAppleIdSignInForAppStoreConnectOnly() {
        let analytics = MockAnalyticsTracker()
        let (apple, cleanApple) = makeAddAccount(.apple, flag: true, analytics: analytics)
        defer { cleanApple() }
        let (play, cleanPlay) = makeAddAccount(.googlePlay, flag: true)
        defer { cleanPlay() }

        XCTAssertTrue(apple.uiState.isAppleIdSignInAvailable)
        XCTAssertFalse(play.uiState.isAppleIdSignInAvailable)
        apple.openAppleIdSignIn()
        XCTAssertTrue(apple.uiState.isShowingAppleIdSignIn)
        XCTAssertEqual(analytics.trackedEvents.last, .buttonTap(.signInWithAppleId, on: .addAccount))
    }

    func testFlagOffKeepsOnlyTheApiKeyForm() {
        let (sut, clean) = makeAddAccount(.apple, flag: false)
        defer { clean() }

        XCTAssertFalse(sut.uiState.isAppleIdSignInAvailable)
        sut.openAppleIdSignIn()
        XCTAssertFalse(sut.uiState.isShowingAppleIdSignIn)
    }

    func testFlagDefaultsOnInDebugBuilds() {
        #if DEBUG
        XCTAssertTrue(FeatureFlag.appleIdSignIn.defaultValue)
        #else
        XCTAssertFalse(FeatureFlag.appleIdSignIn.defaultValue)
        #endif
    }

    func testAuthMethodAnalyticsValue() {
        XCTAssertEqual(AccountAuthMethod.appleIdSignIn.analyticsValue, "apple_id_sign_in")
    }
}
