import XCTest
import StackProtocols
@testable import StackConnect

/// Add Account with the connection guide (flag `accountConnectionGuide`):
/// OFF keeps Add Account exactly as before; ON shows the guide before the
/// first connection only, then the method chooser with the methods this build
/// offers (none when there is a single one), and reopens the guide from
/// "How It Works".
@MainActor
final class AddAccountConnectionGuideTests: XCTestCase {

    private var flagSuite: String!
    private var flagDefaults: UserDefaults!
    private var guideSuite: String!
    private var guideDefaults: UserDefaults!
    private var analytics: MockAnalyticsTracker!
    private var auth: MockGoogleAuthService!

    private let remoteKey = "account_connection_guide_enabled"

    override func setUp() async throws {
        try await super.setUp()
        flagSuite = "AddAccountConnectionGuideTests.flags.\(UUID().uuidString)"
        flagDefaults = UserDefaults(suiteName: flagSuite)
        guideSuite = "AddAccountConnectionGuideTests.guide.\(UUID().uuidString)"
        guideDefaults = UserDefaults(suiteName: guideSuite)
        analytics = MockAnalyticsTracker()
        auth = MockGoogleAuthService()
    }

    override func tearDown() async throws {
        flagDefaults.removePersistentDomain(forName: flagSuite)
        guideDefaults.removePersistentDomain(forName: guideSuite)
        flagDefaults = nil
        guideDefaults = nil
        analytics = nil
        auth = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// - Parameters:
    ///   - guide: the stored flag value, or `nil` for none (default or remote).
    ///   - remote: Remote Config values activated at launch.
    private func flags(
        guide: Bool?,
        appleIdSignIn: Bool = true,
        googleSignIn: Bool = true,
        remote: [String: Bool] = [:]
    ) -> FeatureFlags {
        if let guide {
            flagDefaults.set(guide, forKey: FeatureFlag.accountConnectionGuide.rawValue)
        }
        flagDefaults.set(appleIdSignIn, forKey: FeatureFlag.appleIdSignIn.rawValue)
        flagDefaults.set(googleSignIn, forKey: FeatureFlag.googleSignIn.rawValue)
        return FeatureFlags(defaults: flagDefaults, remoteValues: StubRemoteFeatureValues(values: remote))
    }

    private var guideStore: ConnectionGuideStore {
        ConnectionGuideStore(defaults: guideDefaults)
    }

    private func makeSUT(_ provider: ProviderType, flags: FeatureFlags) -> AddAccountViewModel {
        AddAccountViewModel(
            providerType: provider,
            storage: MockPersistentStorable(),
            keychain: MockKeyStorable(),
            googlePlayConnectionFactory: { _ in MockGooglePlayAccountConnection() },
            analytics: analytics,
            featureFlags: flags,
            googleAuth: auth,
            googleResources: MockGoogleResourceListing(),
            connectionGuide: guideStore
        )
    }

    /// Flag ON with the guide already shown: what every later Add Account sees.
    private func makeSeenSUT(_ provider: ProviderType, appleIdSignIn: Bool = true, googleSignIn: Bool = true) -> AddAccountViewModel {
        guideStore.markGuideShown()
        return makeSUT(provider, flags: flags(guide: true, appleIdSignIn: appleIdSignIn, googleSignIn: googleSignIn))
    }

    // MARK: - Flag definition (kill switch)

    func testFlagDefinition() {
        XCTAssertEqual(FeatureFlag.accountConnectionGuide.rawValue, "featureFlag.accountConnectionGuide")
        XCTAssertEqual(FeatureFlag.accountConnectionGuide.remoteConfigKey, remoteKey)
        XCTAssertTrue(FeatureFlag.accountConnectionGuide.defaultValue, "a kill switch ships ON, in every build")
    }

    func testFlagIsOnWithoutStoredOrRemoteValue() {
        XCTAssertTrue(flags(guide: nil).isEnabled(.accountConnectionGuide))
    }

    func testRemoteFalseTurnsTheFlagOff() {
        XCTAssertFalse(flags(guide: nil, remote: [remoteKey: false]).isEnabled(.accountConnectionGuide))
        XCTAssertTrue(flags(guide: nil, remote: [remoteKey: true]).isEnabled(.accountConnectionGuide))
    }

    func testStoredValueWinsOverRemote() {
        // A launch argument `-featureFlag.accountConnectionGuide YES` lands here.
        XCTAssertTrue(flags(guide: true, remote: [remoteKey: false]).isEnabled(.accountConnectionGuide))
    }

    // MARK: - Flag OFF: Add Account as before

    func testFlagOffKeepsAddAccountAsBeforeForEveryProvider() {
        for provider in ProviderType.allCases {
            let sut = makeSUT(provider, flags: flags(guide: false))

            XCTAssertFalse(sut.uiState.isConnectionGuideEnabled, "\(provider)")
            XCTAssertEqual(sut.uiState.root, .form, "\(provider): no guide, no chooser")
            XCTAssertFalse(sut.uiState.showsMethodChooser, "\(provider): the forms keep their own switch")
            XCTAssertFalse(sut.uiState.isShowingMethodForm)
            XCTAssertFalse(sut.uiState.isShowingConnectionGuide)
        }
    }

    func testFlagOffKeepsTodaysDefaultsAndOptions() {
        let apple = makeSUT(.apple, flags: flags(guide: false))
        XCTAssertEqual(apple.uiState.credentialMode, .keyFile)
        XCTAssertTrue(apple.uiState.isAppleIdSignInAvailable, "the in-form email and password option stays")

        let firebase = makeSUT(.firebase, flags: flags(guide: false))
        XCTAssertEqual(firebase.uiState.credentialMode, .googleSignIn, "Google sign-in stays the primary path")
        XCTAssertTrue(firebase.uiState.isGoogleSignInAvailable)
    }

    func testFlagOffIgnoresEveryGuideAction() {
        let sut = makeSUT(.apple, flags: flags(guide: false))

        sut.connectionGuideDidAppear()
        sut.finishConnectionGuide()
        sut.showConnectionGuide()
        sut.chooseMethod(.apiKey)
        sut.chooseMethod(.appleIdSignIn)

        XCTAssertEqual(sut.uiState.root, .form)
        XCTAssertFalse(sut.uiState.isShowingConnectionGuide)
        XCTAssertFalse(sut.uiState.isShowingMethodForm)
        XCTAssertFalse(sut.uiState.isShowingAppleIdSignIn)
        XCTAssertFalse(guideStore.hasShownGuide, "nothing recorded while OFF")
        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testRemoteKillSwitchBringsBackAddAccountAsBefore() {
        let sut = makeSUT(.apple, flags: flags(guide: nil, remote: [remoteKey: false]))

        XCTAssertFalse(sut.uiState.isConnectionGuideEnabled)
        XCTAssertEqual(sut.uiState.root, .form)
        XCTAssertFalse(sut.uiState.showsMethodChooser)
    }

    func testFlagOffKeepsTheInFormAppleIdOption() {
        let sut = makeSUT(.apple, flags: flags(guide: false))

        sut.openAppleIdSignIn()

        XCTAssertTrue(sut.uiState.isShowingAppleIdSignIn)
        XCTAssertEqual(analytics.trackedEvents, [.buttonTap(.signInWithAppleId, on: .addAccount)])
    }

    // MARK: - Flag ON: the guide before the first connection only

    func testFirstConnectionStartsWithTheGuide() {
        for provider in ProviderType.allCases {
            let sut = makeSUT(provider, flags: flags(guide: true))
            XCTAssertTrue(sut.uiState.isConnectionGuideEnabled)
            XCTAssertEqual(sut.uiState.root, .connectionGuide, "\(provider)")
        }
    }

    func testTheGuideShowsAutomaticallyOnlyTheFirstTime() {
        let first = makeSUT(.apple, flags: flags(guide: true))
        XCTAssertEqual(first.uiState.root, .connectionGuide)

        first.connectionGuideDidAppear()
        XCTAssertTrue(guideStore.hasShownGuide)

        for provider in ProviderType.allCases {
            let later = makeSUT(provider, flags: flags(guide: true))
            XCTAssertNotEqual(later.uiState.root, .connectionGuide, "\(provider): once, for every provider")
        }
    }

    func testTheGuideIsRecordedOnlyOnceItAppeared() {
        _ = makeSUT(.apple, flags: flags(guide: true))

        XCTAssertFalse(guideStore.hasShownGuide)
        XCTAssertEqual(makeSUT(.apple, flags: flags(guide: true)).uiState.root, .connectionGuide)
    }

    func testFinishingTheGuideGoesOnToTheChooser() {
        let sut = makeSUT(.apple, flags: flags(guide: true))

        sut.finishConnectionGuide()

        XCTAssertEqual(sut.uiState.root, .methods)
        XCTAssertTrue(guideStore.hasShownGuide, "Skip / Continue record it too")
        XCTAssertTrue(analytics.trackedEvents.isEmpty, "Skip and Continue are tracked by the guide's buttons")
        sut.finishConnectionGuide()
        XCTAssertEqual(sut.uiState.root, .methods, "only from the guide")
    }

    func testFinishingTheGuideGoesStraightToTheFormWithASingleMethod() {
        let sut = makeSUT(.apple, flags: flags(guide: true, appleIdSignIn: false))

        sut.finishConnectionGuide()

        XCTAssertEqual(sut.uiState.root, .form)
    }

    // MARK: - Chooser: only the available methods

    func testChooserOffersEmailAndPasswordNextToTheApiKey() {
        let sut = makeSeenSUT(.apple)

        XCTAssertEqual(sut.uiState.availableMethods, [.apiKey, .appleIdSignIn])
        XCTAssertTrue(sut.uiState.showsMethodChooser)
        XCTAssertEqual(sut.uiState.root, .methods)
    }

    func testChooserOffersGoogleSignInNextToTheServiceAccount() {
        for provider in [ProviderType.firebase, .googlePlay] {
            let sut = makeSeenSUT(provider)

            XCTAssertEqual(sut.uiState.availableMethods, [.googleSignIn, .serviceAccount], "\(provider)")
            XCTAssertEqual(sut.uiState.root, .methods, "\(provider)")
        }
    }

    func testMethodsOfAnotherProviderAreNeverOffered() {
        let apple = makeSeenSUT(.apple)
        apple.chooseMethod(.googleSignIn)
        apple.chooseMethod(.serviceAccount)
        XCTAssertFalse(apple.uiState.isShowingMethodForm)

        let firebase = makeSeenSUT(.firebase)
        firebase.chooseMethod(.apiKey)
        firebase.chooseMethod(.appleIdSignIn)
        XCTAssertFalse(firebase.uiState.isShowingMethodForm)
        XCTAssertFalse(firebase.uiState.isShowingAppleIdSignIn)

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    // MARK: - A single method skips the chooser

    func testApiKeyAloneSkipsTheChooser() {
        let sut = makeSeenSUT(.apple, appleIdSignIn: false)

        XCTAssertEqual(sut.uiState.availableMethods, [.apiKey])
        XCTAssertFalse(sut.uiState.showsMethodChooser)
        XCTAssertEqual(sut.uiState.root, .form)
        XCTAssertEqual(sut.uiState.credentialMode, .keyFile)
        sut.chooseMethod(.apiKey)
        XCTAssertFalse(sut.uiState.isShowingMethodForm, "nothing to choose: the form is already the root")
    }

    func testServiceAccountAloneSkipsTheChooser() {
        let flagOff = makeSeenSUT(.firebase, googleSignIn: false)
        XCTAssertEqual(flagOff.uiState.availableMethods, [.serviceAccount])
        XCTAssertEqual(flagOff.uiState.root, .form)
        XCTAssertEqual(flagOff.uiState.credentialMode, .keyFile)

        auth.isConfigured = false
        let unconfigured = makeSUT(.googlePlay, flags: flags(guide: true))
        XCTAssertEqual(unconfigured.uiState.availableMethods, [.serviceAccount], "no OAuth client ID in this build")
        XCTAssertEqual(unconfigured.uiState.root, .form)
    }

    // MARK: - Choosing a method

    func testChoosingTheApiKeyPushesItsForm() {
        let sut = makeSeenSUT(.apple)

        sut.chooseMethod(.apiKey)

        XCTAssertTrue(sut.uiState.isShowingMethodForm)
        XCTAssertEqual(sut.uiState.chosenMethod, .apiKey)
        XCTAssertEqual(sut.uiState.credentialMode, .keyFile)
        XCTAssertFalse(sut.uiState.isShowingAppleIdSignIn)
        XCTAssertEqual(analytics.trackedEvents, [.buttonTap(.useApiKey, on: .addAccountMethod)])
    }

    func testChoosingEmailAndPasswordOpensItsScreens() {
        let sut = makeSeenSUT(.apple)

        sut.chooseMethod(.appleIdSignIn)

        XCTAssertTrue(sut.uiState.isShowingAppleIdSignIn)
        XCTAssertFalse(sut.uiState.isShowingMethodForm)
        XCTAssertEqual(analytics.trackedEvents, [.buttonTap(.useAppleIdSignIn, on: .addAccountMethod)],
                       "reported on the chooser, not as the form's sign_in_with_apple_id")
    }

    func testChoosingGoogleOrTheServiceAccountPicksTheForm() {
        let sut = makeSeenSUT(.firebase)

        sut.chooseMethod(.serviceAccount)
        XCTAssertTrue(sut.uiState.isShowingMethodForm)
        XCTAssertEqual(sut.uiState.credentialMode, .keyFile)
        XCTAssertFalse(sut.uiState.isGoogleSignInMode)

        sut.uiState.isShowingMethodForm = false // back to the chooser
        sut.chooseMethod(.googleSignIn)
        XCTAssertTrue(sut.uiState.isShowingMethodForm)
        XCTAssertTrue(sut.uiState.isGoogleSignInMode)
        XCTAssertEqual(sut.uiState.chosenMethod, .googleSignIn)

        XCTAssertEqual(analytics.trackedEvents, [
            .buttonTap(.useServiceAccount, on: .addAccountMethod),
            .buttonTap(.useGoogleSignIn, on: .addAccountMethod)
        ])
    }

    func testChoosingClearsAPreviousError() {
        let sut = makeSeenSUT(.apple)
        sut.uiState.validationError = "Earlier"

        sut.chooseMethod(.apiKey)

        XCTAssertNil(sut.uiState.validationError)
    }

    func testChoosingIsRefusedWhileBusy() {
        let sut = makeSeenSUT(.apple)
        sut.uiState.isValidating = true

        sut.chooseMethod(.apiKey)

        XCTAssertFalse(sut.uiState.isShowingMethodForm)
    }

    // MARK: - Reopening the guide from "How It Works"

    func testHowItWorksReopensTheGuideFromTheChooser() {
        let sut = makeSeenSUT(.apple)

        sut.showConnectionGuide()

        XCTAssertTrue(sut.uiState.isShowingConnectionGuide)
        XCTAssertEqual(sut.uiState.root, .methods, "the guide opens over Add Account")
        XCTAssertEqual(analytics.trackedEvents, [.buttonTap(.howItWorks, on: .addAccountMethod)])
    }

    func testHowItWorksReopensTheGuideFromTheForm() {
        let pushed = makeSeenSUT(.apple)
        pushed.chooseMethod(.apiKey)
        pushed.showConnectionGuide()
        XCTAssertTrue(pushed.uiState.isShowingConnectionGuide)
        XCTAssertEqual(analytics.trackedEvents.last, .buttonTap(.howItWorks, on: .addAccount))

        let single = makeSeenSUT(.apple, appleIdSignIn: false)
        single.showConnectionGuide()
        XCTAssertTrue(single.uiState.isShowingConnectionGuide)
        XCTAssertEqual(analytics.trackedEvents.last, .buttonTap(.howItWorks, on: .addAccount))
    }

    func testHowItWorksCanBeOpenedAgainAfterClosing() {
        let sut = makeSeenSUT(.firebase)

        sut.showConnectionGuide()
        sut.showConnectionGuide()
        XCTAssertEqual(analytics.taps(of: .howItWorks).count, 1, "already open")

        sut.uiState.isShowingConnectionGuide = false // Done or swipe down
        sut.showConnectionGuide()
        XCTAssertTrue(sut.uiState.isShowingConnectionGuide)
        XCTAssertEqual(analytics.taps(of: .howItWorks).count, 2)
    }

    func testHowItWorksIsNotOfferedOverTheGuideItself() {
        let sut = makeSUT(.apple, flags: flags(guide: true))

        sut.showConnectionGuide()

        XCTAssertFalse(sut.uiState.isShowingConnectionGuide)
    }

    func testReopeningNeverChangesWhetherTheGuideShowsOnItsOwn() {
        let sut = makeSeenSUT(.apple)
        sut.showConnectionGuide()
        sut.connectionGuideDidAppear()

        XCTAssertTrue(guideStore.hasShownGuide)
        XCTAssertEqual(makeSUT(.apple, flags: flags(guide: true)).uiState.root, .methods)
    }

    // MARK: - Store

    func testStoreRemembersTheGuideAcrossInstances() {
        XCTAssertFalse(ConnectionGuideStore(defaults: guideDefaults).hasShownGuide)

        ConnectionGuideStore(defaults: guideDefaults).markGuideShown()

        XCTAssertTrue(ConnectionGuideStore(defaults: guideDefaults).hasShownGuide)
        XCTAssertTrue(guideDefaults.bool(forKey: "connectionGuide.hasShownAutomatically"), "stable key")
    }

    func testInitialRoot() {
        XCTAssertEqual(AddAccountViewModel.initialRoot(isGuideEnabled: false, hasShownGuide: false, methodCount: 2), .form)
        XCTAssertEqual(AddAccountViewModel.initialRoot(isGuideEnabled: true, hasShownGuide: false, methodCount: 1), .connectionGuide)
        XCTAssertEqual(AddAccountViewModel.initialRoot(isGuideEnabled: true, hasShownGuide: true, methodCount: 2), .methods)
        XCTAssertEqual(AddAccountViewModel.initialRoot(isGuideEnabled: true, hasShownGuide: true, methodCount: 1), .form)
    }
}
