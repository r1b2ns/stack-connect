import XCTest
import StackProtocols
@testable import StackConnect

/// The trust panel of the App Store Connect email and password screen and
/// "How Your Password Is Used" (flag `accountConnectionGuide`), and the
/// screen's wording, which never reads as Apple's "Sign in with Apple".
@MainActor
final class AppleIdSignInTrustPanelTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var analytics: MockAnalyticsTracker!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "AppleIdSignInTrustPanelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        analytics = nil
        try await super.tearDown()
    }

    private func makeSUT(
        guide: Bool?,
        remote: [String: Bool] = [:],
        mode: AppleIdSignInMode = .addAccounts
    ) -> AppleIdSignInViewModel {
        if let guide {
            defaults.set(guide, forKey: FeatureFlag.accountConnectionGuide.rawValue)
        }
        return AppleIdSignInViewModel(
            mode: mode,
            storage: MockPersistentStorable(),
            keychain: MockKeyStorable(),
            sessionStatus: MockAppleSessionStatus(),
            roleResolver: MockAppleSessionRoleResolver(),
            analytics: analytics,
            featureFlags: FeatureFlags(defaults: defaults, remoteValues: StubRemoteFeatureValues(values: remote)),
            makeSignIn: { _ in MockAppleIdSignIn() }
        )
    }

    // MARK: - Flag

    func testFlagOnShowsTheTrustPanel() {
        XCTAssertTrue(makeSUT(guide: true).uiState.showsTrustPanel)
        XCTAssertTrue(makeSUT(guide: nil).uiState.showsTrustPanel, "ON by default")
        XCTAssertTrue(makeSUT(guide: nil, mode: .signInAgain(appleId: "dev@example.com")).uiState.showsTrustPanel,
                      "also when signing in again")
    }

    func testFlagOffKeepsThePasswordScreenAsBefore() {
        XCTAssertFalse(makeSUT(guide: false).uiState.showsTrustPanel)
        XCTAssertFalse(makeSUT(guide: nil, remote: ["account_connection_guide_enabled": false]).uiState.showsTrustPanel,
                       "the remote kill switch")
    }

    // MARK: - How Your Password Is Used

    func testHowYourPasswordIsUsedOpensTheSheet() {
        let sut = makeSUT(guide: true)

        sut.showPasswordUsage()
        sut.showPasswordUsage()

        XCTAssertTrue(sut.uiState.isShowingPasswordUsage)
        XCTAssertEqual(analytics.trackedEvents, [.buttonTap(.howPasswordIsUsed, on: .appleIdSignIn)], "once while open")

        sut.uiState.isShowingPasswordUsage = false // Done
        sut.showPasswordUsage()
        XCTAssertEqual(analytics.taps(of: .howPasswordIsUsed).count, 2)
    }

    func testHowYourPasswordIsUsedIsUnavailableWhileOff() {
        let sut = makeSUT(guide: false)

        sut.showPasswordUsage()

        XCTAssertFalse(sut.uiState.isShowingPasswordUsage)
        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testPasswordUsageStepsLinkOnlyTheRepositoryTheKeychainStoreAndThePrivacyPolicy() {
        let steps = ApplePasswordTrustContent.steps
        let allowed: Set<URL> = [ProjectLinks.repository, ProjectLinks.applePasswordKeychainStore, ProjectLinks.privacyPolicy]

        XCTAssertEqual(steps.map(\.number), [1, 2, 3, 4])
        XCTAssertTrue(steps.compactMap(\.link).allSatisfy { allowed.contains($0.url) })
        XCTAssertEqual(steps[2].link?.url, ProjectLinks.applePasswordKeychainStore)
        XCTAssertEqual(steps[3].link?.url, ProjectLinks.privacyPolicy)
        XCTAssertEqual(steps[1].title, String(localized: "Sent only to Apple, over an encrypted connection, to sign you in"))
        XCTAssertTrue(steps[2].title.contains(String(localized: "Save password on this device")),
                      "names the password screen's toggle exactly as it is translated")
        XCTAssertEqual(steps.compactMap(\.link).map(\.button), [.sourceCode, .sourceFile, .privacyPolicy])
    }

    func testPasswordCopyNamesNoPrivateEndpointAndSaysThisDevice() {
        let texts = ApplePasswordTrustContent.panelItems.map(\.text)
            + ApplePasswordTrustContent.steps.flatMap { [$0.title, $0.detail] }

        XCTAssertEqual(ApplePasswordTrustContent.panelItems.count, 4)
        for text in texts {
            XCTAssertFalse(text.contains("idmsa"), text)
            XCTAssertFalse(text.contains("iris"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("iPhone"), text)
            XCTAssertFalse(text.contains("Sign in with Apple"), text)
        }
        XCTAssertFalse(ApplePasswordTrustContent.panelItems.map(\.systemImage).contains("apple.logo"))
    }

    // MARK: - Wording (unconditional)

    func testRenamedSessionAccountMessages() {
        let session = AccountModel(name: "Session", providerType: .apple, authMethod: .appleIdSignIn)
        XCTAssertEqual(
            session.exportUnavailableReason,
            String(localized: "Accounts added with email and password can't be exported: the session is your personal Apple ID login. Share an App Store Connect API key instead.")
        )

        let bundle = BundleIdentifierModel(id: "B1", identifier: "com.example.app", name: "App", platform: "IOS", seedId: nil)
        let identifier = IdentifierDetailViewModel(account: session, bundleId: bundle, keychain: MockKeyStorable(), analytics: MockAnalyticsTracker())
        XCTAssertEqual(
            identifier.uiState.renameOrDeleteUnavailableReason,
            String(localized: "Renaming or deleting an identifier needs an App Store Connect API key. Accounts added with email and password can't do it: use developer.apple.com instead.")
        )
        XCTAssertEqual(AccountConnectionMethod.appleIdSignIn.title, String(localized: "Sign in with email and password"))
    }
}
