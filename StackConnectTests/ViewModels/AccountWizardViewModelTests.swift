import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// The account wizard's step engine driving the existing connection logic:
/// moving between steps, the Credentials components per auth style, the
/// connection guide (and its kill switch), the import, reconnecting and the
/// done screen.
@MainActor
final class AccountWizardViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private var auth: MockGoogleAuthService!
    private var resources: MockGoogleResourceListing!
    private var appleFlow: MockAppleIdSignIn!
    private var appleStatus: MockAppleSessionStatus!
    private var guideDefaults: UserDefaults!
    private var suites: [String] = []
    private var appleModes: [AppleIdSignInMode] = []
    private var syncRequests = 0

    private let password = "aVeryStrongPass123"

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        auth = MockGoogleAuthService()
        resources = MockGoogleResourceListing()
        appleFlow = MockAppleIdSignIn()
        appleStatus = MockAppleSessionStatus()
        appleModes = []
        syncRequests = 0
        let suite = "AccountWizardViewModelTests.guide.\(UUID().uuidString)"
        suites.append(suite)
        guideDefaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        suites = []
        storage = nil
        keychain = nil
        analytics = nil
        auth = nil
        resources = nil
        appleFlow = nil
        appleStatus = nil
        guideDefaults = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func flags(signIn: Bool, guide: Bool = true) -> FeatureFlags {
        let suite = "AccountWizardViewModelTests.flags.\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.set(signIn, forKey: FeatureFlag.appleIdSignIn.rawValue)
        defaults.set(signIn, forKey: FeatureFlag.googleSignIn.rawValue)
        defaults.set(true, forKey: FeatureFlag.googlePlayAccounts.rawValue)
        defaults.set(guide, forKey: FeatureFlag.accountConnectionGuide.rawValue)
        return FeatureFlags(defaults: defaults, remoteValues: StubRemoteFeatureValues())
    }

    private func makeSUT(
        _ entry: AccountWizardEntry = .chooseKind,
        signIn: Bool = true,
        guide: Bool = true,
        guideAlreadyShown: Bool = true
    ) -> AccountWizardViewModel {
        let featureFlags = flags(signIn: signIn, guide: guide)
        let guideStore = ConnectionGuideStore(defaults: guideDefaults)
        if guideAlreadyShown { guideStore.markGuideShown() }
        return AccountWizardViewModel(
            entry: entry,
            storage: storage,
            keychain: keychain,
            analytics: analytics,
            featureFlags: featureFlags,
            googleAuth: auth,
            connectionGuide: guideStore,
            makeConnection: { [unowned self] provider, mode in
                AddAccountViewModel(
                    providerType: provider,
                    storage: self.storage,
                    keychain: self.keychain,
                    googlePlayConnectionFactory: { _ in MockGooglePlayAccountConnection() },
                    analytics: self.analytics,
                    featureFlags: featureFlags,
                    googleAuth: self.auth,
                    googleResources: self.resources,
                    credentialMode: mode
                )
            },
            makeAppleSignIn: { [unowned self] mode in
                self.appleModes.append(mode)
                return AppleIdSignInViewModel(
                    mode: mode,
                    storage: self.storage,
                    keychain: self.keychain,
                    sessionStatus: self.appleStatus,
                    roleResolver: MockAppleSessionRoleResolver(),
                    analytics: self.analytics,
                    featureFlags: featureFlags,
                    makeSignIn: { [unowned self] _ in self.appleFlow }
                )
            },
            requestSync: { [unowned self] in self.syncRequests += 1 }
        )
    }

    private func makeImportFile(name: String = "Shared Team", provider: String = "apple") throws -> URL {
        let payload: [String: Any] = [
            "name": name,
            "providerType": provider,
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "credentials": ["issuerID": "issuer", "privateKeyID": "kid", "privateKey": "pk"]
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wizard-\(UUID().uuidString).scexport")
        try AccountCrypto.encrypt(json: json, password: password).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Type and Method

    func testChooseKindStartsOnTheTypeStep() {
        let sut = makeSUT()

        XCTAssertEqual(sut.uiState.step, .type)
        XCTAssertNil(sut.primaryTitle, "A row tap goes on")
        XCTAssertFalse(sut.canGoBack)
        XCTAssertNil(sut.connection)
    }

    func testAKindWithOneMethodGoesStraightToItsCredentials() {
        let sut = makeSUT(signIn: false)

        sut.chooseKind(.provider(.apple))

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.uiState.method, .apiKey)
        XCTAssertEqual(sut.uiState.steps, [.type, .credentials, .review])
        XCTAssertEqual(sut.uiState.stepIndex, 1)
        XCTAssertEqual(sut.uiState.progress, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(sut.connection?.uiState.providerType, .apple)
        XCTAssertEqual(sut.connection?.uiState.credentialMode, .keyFile)
        XCTAssertTrue(analytics.trackedEvents.contains(.buttonTap(.appleProvider, on: .accountWizardType)))
    }

    func testAKindWithTwoMethodsAsksForOneThenGoesOn() {
        let sut = makeSUT()

        sut.chooseKind(.provider(.apple))
        XCTAssertEqual(sut.uiState.step, .method)
        XCTAssertNil(sut.uiState.method)

        sut.chooseMethod(.apiKey)

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.uiState.steps, [.type, .method, .credentials, .review])
        XCTAssertEqual(analytics.trackedEvents.last, .buttonTap(.useApiKey, on: .accountWizardMethod))
    }

    func testAMethodOfAnotherKindIsRefused() {
        let sut = makeSUT()
        sut.chooseKind(.provider(.apple))

        sut.chooseMethod(.googleSignIn)

        XCTAssertEqual(sut.uiState.step, .method)
        XCTAssertNil(sut.uiState.method)
    }

    func testStoreEntrySkipsTheTypeStep() {
        let sut = makeSUT(.kind(.provider(.firebase)), signIn: false)

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.uiState.steps, [.credentials, .review])
        XCTAssertFalse(sut.canGoBack, "The first step has only Cancel")
        XCTAssertEqual(sut.connection?.uiState.providerType, .firebase)
    }

    // MARK: - Key file credentials

    func testApiKeyCredentialsNeedTheThreeFieldsThenGoToReview() async {
        let sut = makeSUT(signIn: false)
        sut.chooseKind(.provider(.apple))
        XCTAssertFalse(sut.canContinue)

        sut.connection?.uiState.issuerID = "issuer"
        sut.connection?.uiState.privateKeyID = "KEY"
        XCTAssertFalse(sut.canContinue)
        sut.connection?.uiState.privateKey = "pk"
        XCTAssertTrue(sut.canContinue)

        await sut.primaryAction()

        XCTAssertEqual(sut.uiState.step, .review)
        XCTAssertFalse(sut.canContinue, "Review needs a name")
        sut.connection?.uiState.accountName = "Acme"
        XCTAssertTrue(sut.canContinue)
        XCTAssertEqual(sut.primaryTitle, String(localized: "Connect Account", comment: "Account wizard: last button, adds the account(s)."))
    }

    func testBackKeepsWhatWasTyped() async {
        let sut = makeSUT()
        sut.chooseKind(.provider(.apple))
        sut.chooseMethod(.apiKey)
        let engine = sut.connection
        sut.connection?.uiState.issuerID = "issuer"

        sut.goBack()
        XCTAssertEqual(sut.uiState.step, .method)
        sut.chooseMethod(.apiKey)

        XCTAssertTrue(sut.connection === engine)
        XCTAssertEqual(sut.connection?.uiState.issuerID, "issuer")
    }

    func testChoosingAnotherKindStartsFresh() {
        let sut = makeSUT(signIn: false)
        sut.chooseKind(.provider(.apple))
        sut.connection?.uiState.issuerID = "issuer"

        sut.goBack()
        XCTAssertEqual(sut.uiState.step, .type)
        sut.chooseKind(.provider(.firebase))

        XCTAssertEqual(sut.connection?.uiState.providerType, .firebase)
        XCTAssertEqual(sut.uiState.method, .serviceAccount)
    }

    func testBackToTheTypeStepShowsTheNeutralHeader() {
        let sut = makeSUT()
        XCTAssertNil(sut.uiState.tintProvider)
        XCTAssertEqual(sut.uiState.stepCount, 3)

        sut.chooseKind(.provider(.firebase))
        XCTAssertEqual(sut.uiState.step, .method)
        XCTAssertEqual(sut.uiState.tintProvider, .firebase)
        XCTAssertEqual(sut.uiState.stepCount, 4)

        sut.goBack()

        XCTAssertEqual(sut.uiState.step, .type)
        XCTAssertNil(sut.uiState.tintProvider, "No store tint while choosing the kind")
        XCTAssertEqual(sut.uiState.stepIndex, 0)
        XCTAssertEqual(sut.uiState.stepCount, 3, "Step 1 of 3, as before choosing")
        XCTAssertEqual(sut.uiState.progress, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(AccountWizardCopy.stepLabel(for: sut.uiState),
                       AccountWizardCopy.stepLabel(for: makeSUT().uiState))
        XCTAssertEqual(sut.uiState.kind?.kind, .provider(.firebase), "The choice is kept for moving on again")

        sut.chooseKind(.provider(.firebase))
        XCTAssertEqual(sut.uiState.step, .method)
        XCTAssertEqual(sut.uiState.stepCount, 4)
    }

    func testGooglePlayServiceAccountConnectsAndShowsTheDoneScreen() async throws {
        let sut = makeSUT(.kind(.provider(.googlePlay)), signIn: false)
        sut.connection?.uiState.googlePlayJSON = GooglePlayTestFixtures.serviceAccountJSON()
        await sut.primaryAction()
        XCTAssertEqual(sut.uiState.step, .review)
        sut.connection?.uiState.accountName = "Play Team"

        await sut.primaryAction()

        XCTAssertEqual(sut.uiState.result, AccountWizardResult(provider: .googlePlay, names: ["Play Team"], isReconnect: false))
        XCTAssertNil(sut.primaryTitle)
        XCTAssertFalse(sut.canGoBack)
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(saved.map(\.name), ["Play Team"])
    }

    func testAFailedSaveStaysOnReviewWithTheError() async {
        let sut = makeSUT(.kind(.provider(.googlePlay)), signIn: false)
        sut.connection?.uiState.googlePlayJSON = #"{"type": "service_account""#
        await sut.primaryAction()
        sut.connection?.uiState.accountName = "Play Team"

        await sut.primaryAction()

        XCTAssertNil(sut.uiState.result)
        XCTAssertEqual(sut.uiState.step, .review)
        XCTAssertNotNil(sut.connection?.uiState.validationError)
    }

    // MARK: - Web sign-in

    func testGoogleSignInListsTheAppsAndMovesToItems() async {
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.playAppsResult = .success([
            GoogleAccessibleResource(id: "com.a", title: "Alpha", subtitle: "com.a")
        ])
        let sut = makeSUT(.kind(.provider(.googlePlay)))
        sut.chooseMethod(.googleSignIn)
        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.primaryTitle, String(localized: "Continue with Google", comment: "Account wizard: opens Google's sign-in page."))

        await sut.primaryAction()

        XCTAssertEqual(sut.uiState.step, .items)
        XCTAssertTrue(sut.canContinue)
        await sut.primaryAction()
        XCTAssertEqual(sut.uiState.step, .review)
        XCTAssertEqual(sut.connection?.uiState.accountName, "dev@example.com")

        await sut.primaryAction()

        XCTAssertEqual(sut.uiState.result?.names, ["dev@example.com"])
    }

    func testBackFromItemsToGoogleSignInDoesNotJumpForwardAgain() async {
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.firebaseProjectsResult = .success([GoogleAccessibleResource(id: "p1", title: "Prod", subtitle: nil)])
        let sut = makeSUT(.kind(.provider(.firebase)))
        sut.chooseMethod(.googleSignIn)
        await sut.primaryAction()
        XCTAssertEqual(sut.uiState.step, .items)

        sut.goBack()

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.primaryTitle, String(localized: "Continue"), "Signed in already: Continue goes on")
        await sut.primaryAction()
        XCTAssertEqual(sut.uiState.step, .items)
    }

    // MARK: - Email and password

    func testEmailAndPasswordFollowsTheSignInThroughCodeTeamsAndReview() async throws {
        appleFlow.startResults = [.success(.needsCode(methods: [.trustedDevice], phones: [], codeLength: 6, delivery: .trustedDevices))]
        appleFlow.submitResults = [.success(.done(teams: [.fixture(1, "Acme"), .fixture(2, "Client")]))]
        let sut = makeSUT(.kind(.provider(.apple)))
        sut.chooseMethod(.appleIdSignIn)
        XCTAssertEqual(appleModes, [.addAccounts])
        XCTAssertFalse(sut.appleSignIn?.uiState.savesPassword ?? true, "Save password is off by default")

        sut.appleSignIn?.uiState.email = "dev@example.com"
        sut.appleSignIn?.uiState.password = "secret"
        await sut.primaryAction()
        XCTAssertEqual(sut.uiState.step, .code)

        await sut.appleSignIn?.updateCode("123456")
        XCTAssertEqual(sut.uiState.step, .items, "A complete code is submitted on its own")

        await sut.primaryAction()
        XCTAssertEqual(sut.uiState.step, .review)
        await sut.primaryAction()

        XCTAssertEqual(sut.uiState.result, AccountWizardResult(provider: .apple, names: ["Acme", "Client"], isReconnect: false))
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(Set(saved.map(\.name)), ["Acme", "Client"])
    }

    func testBackFromTheCodeStartsTheSignInOver() async {
        appleFlow.startResults = [.success(.needsCode(methods: [.trustedDevice], phones: [], codeLength: 6, delivery: .trustedDevices))]
        let sut = makeSUT(.kind(.provider(.apple)))
        sut.chooseMethod(.appleIdSignIn)
        sut.appleSignIn?.uiState.email = "dev@example.com"
        sut.appleSignIn?.uiState.password = "secret"
        await sut.primaryAction()

        sut.goBack()

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.appleSignIn?.uiState.step, .credentials)
    }

    // MARK: - Connection guide (flag `accountConnectionGuide`)

    func testTheGuideOpensOnItsOwnBeforeTheFirstConnectionOnly() {
        let first = makeSUT(signIn: false, guideAlreadyShown: false)
        first.chooseKind(.provider(.apple))

        first.credentialsStepDidAppear()

        XCTAssertEqual(first.uiState.guide, .firstConnection)
        first.dismissConnectionGuide()

        let second = makeSUT(signIn: false, guideAlreadyShown: false)
        second.chooseKind(.provider(.apple))
        second.credentialsStepDidAppear()
        XCTAssertNil(second.uiState.guide, "Recorded as shown the first time")
    }

    func testHowItWorksReopensTheGuide() {
        let sut = makeSUT(signIn: false)
        sut.chooseKind(.provider(.firebase))

        sut.showConnectionGuide()

        XCTAssertEqual(sut.uiState.guide, .reopened)
        XCTAssertEqual(sut.guideMethods, [.serviceAccount])
        XCTAssertEqual(analytics.trackedEvents.last, .buttonTap(.howItWorks, on: .accountWizardCredentials))
    }

    func testTheKillSwitchHidesTheGuide() {
        let sut = makeSUT(signIn: false, guide: false, guideAlreadyShown: false)
        sut.chooseKind(.provider(.apple))

        sut.credentialsStepDidAppear()
        sut.showConnectionGuide()

        XCTAssertFalse(sut.uiState.isConnectionGuideEnabled)
        XCTAssertNil(sut.uiState.guide)
    }

    func testTheGuideIsNeverShownForAnImport() {
        let sut = makeSUT(.kind(.importFile), guideAlreadyShown: false)

        sut.credentialsStepDidAppear()
        sut.showConnectionGuide()

        XCTAssertNil(sut.uiState.guide)
    }

    // MARK: - Import

    func testImportDecryptsThenImportsUnderTheNameChosen() async throws {
        let url = try makeImportFile()
        let sut = makeSUT(.kind(.importFile))
        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertFalse(sut.canContinue)

        sut.selectImportFile(url)
        sut.uiState.importFile.password = password
        await sut.primaryAction()

        XCTAssertEqual(sut.uiState.step, .review)
        XCTAssertEqual(sut.uiState.importFile.accountName, "Shared Team")
        sut.uiState.importFile.accountName = "Renamed"
        await sut.primaryAction()

        XCTAssertEqual(sut.uiState.result, AccountWizardResult(provider: .apple, names: ["Renamed"], isReconnect: false))
        XCTAssertTrue(sut.uiState.importFile.password.isEmpty, "The file password isn't kept")
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(saved.map(\.name), ["Renamed"])
        XCTAssertEqual(saved.first?.origin, .imported)
        XCTAssertEqual(analytics.results(of: .importAccount), [.success])
    }

    func testImportWithTheWrongPasswordStaysOnCredentials() async throws {
        let url = try makeImportFile()
        let sut = makeSUT(.kind(.importFile))
        sut.selectImportFile(url)
        sut.uiState.importFile.password = "wrong-password"

        await sut.primaryAction()

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertNotNil(sut.uiState.errorMessage)
        XCTAssertFalse(sut.uiState.importFile.isDecrypted)
    }

    func testReimportReplacesTheExpiredAccountInPlace() async throws {
        let expired = AccountModel(name: "Shared", providerType: .apple, origin: .imported, expirationDate: Date(timeIntervalSinceNow: -60))
        try await storage.save(expired, id: expired.id)
        let url = try makeImportFile(name: "From the file")
        let sut = makeSUT(.reconnect(expired))
        XCTAssertEqual(sut.uiState.steps, [.credentials])
        XCTAssertEqual(sut.primaryTitle, String(localized: "Import Again", comment: "Account wizard: re-imports the file of an expired shared account."))

        sut.selectImportFile(url)
        sut.uiState.importFile.password = password
        await sut.primaryAction()

        XCTAssertEqual(sut.uiState.result, AccountWizardResult(provider: .apple, names: ["Shared"], isReconnect: true))
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(saved.map(\.id), [expired.id])
        XCTAssertNil(saved.first?.expirationDate)
        XCTAssertEqual(analytics.results(of: .reimportAccount), [.success])
    }

    // MARK: - Reconnect

    func testReconnectingAnAppleIdAccountSignsInAgainWithTheSameAppleId() async {
        let account = AccountModel(name: "Personal", providerType: .apple, authMethod: .appleIdSignIn)
        keychain.setObject(
            AppleCredentials(webSession: AppleWebSessionReference(appleId: "dev@example.com", teamId: 1, teamName: "Acme")),
            forKey: "credentials.\(account.id)"
        )
        appleFlow.startResults = [.success(.needsCode(methods: [.trustedDevice], phones: [], codeLength: 6, delivery: .trustedDevices))]
        appleFlow.submitResults = [.success(.done(teams: [.fixture(1, "Acme")]))]

        let sut = makeSUT(.reconnect(account), signIn: false)

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.uiState.steps, [.credentials, .code])
        XCTAssertEqual(appleModes, [.signInAgain(appleId: "dev@example.com")])
        XCTAssertFalse(sut.appleSignIn?.uiState.isEmailEditable ?? true)

        sut.appleSignIn?.uiState.password = "secret"
        await sut.primaryAction()
        XCTAssertEqual(sut.uiState.step, .code)
        await sut.appleSignIn?.updateCode("123456")

        XCTAssertEqual(sut.uiState.result, AccountWizardResult(provider: .apple, names: ["Personal"], isReconnect: true))
        XCTAssertEqual(syncRequests, 1)
    }

    func testReconnectingAnAppleIdAccountWithoutAReferenceAsksForTheAppleIdAndRestoresIt() async throws {
        let account = AccountModel(name: "Acme", providerType: .apple, authMethod: .appleIdSignIn)
        try await storage.save(account, id: account.id)
        appleFlow.startResults = [.success(.needsCode(methods: [.trustedDevice], phones: [], codeLength: 6, delivery: .trustedDevices))]
        appleFlow.submitResults = [.success(.done(teams: [.fixture(7, "Other"), .fixture(1, "Acme")]))]

        let sut = makeSUT(.reconnect(account), signIn: false)

        XCTAssertEqual(sut.uiState.steps, [.credentials, .code], "still a reconnect: no team step, nothing added")
        XCTAssertEqual(appleModes, [.reconnectAccount(accountId: account.id, accountName: "Acme")])
        XCTAssertEqual(sut.appleSignIn?.uiState.isEmailEditable, true, "never a read-only empty Apple ID")

        sut.appleSignIn?.uiState.email = "dev@example.com"
        sut.appleSignIn?.uiState.password = "secret"
        await sut.primaryAction()
        XCTAssertEqual(sut.uiState.step, .code)
        await sut.appleSignIn?.updateCode("123456")

        XCTAssertEqual(sut.uiState.result, AccountWizardResult(provider: .apple, names: ["Acme"], isReconnect: true))
        let reference = AppleSessionReferences.reference(of: account, keychain: keychain)
        XCTAssertEqual(reference, AppleWebSessionReference(appleId: "dev@example.com", teamId: 1, teamName: "Acme"),
                       "the next reconnect resolves")
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(saved.map(\.id), [account.id], "no duplicate account")

        // The next reconnect signs in again with the same Apple ID.
        appleModes = []
        _ = makeSUT(.reconnect(account), signIn: false)
        XCTAssertEqual(appleModes, [.signInAgain(appleId: "dev@example.com")])
    }

    // MARK: - Done

    func testAddAnotherAccountStartsAgainAtTheType() async throws {
        let url = try makeImportFile()
        let sut = makeSUT(.kind(.importFile))
        sut.selectImportFile(url)
        sut.uiState.importFile.password = password
        await sut.primaryAction()
        await sut.primaryAction()
        XCTAssertNotNil(sut.uiState.result)

        sut.addAnotherAccount()

        XCTAssertNil(sut.uiState.result)
        XCTAssertEqual(sut.uiState.entry, .chooseKind)
        XCTAssertEqual(sut.uiState.step, .type)
        XCTAssertNil(sut.uiState.kind)
        XCTAssertNil(sut.uiState.importFile.fileURL)
        XCTAssertEqual(analytics.trackedEvents.last, .buttonTap(.addAnotherAccount, on: .accountWizardDone))
    }

    func testClosingSignsOutAnUnusedNewGoogleLogin() async {
        auth.signInResult = .success(MockGoogleAuthService.result(isNewLogin: true))
        resources.playAppsResult = .success([GoogleAccessibleResource(id: "com.a", title: "Alpha", subtitle: nil)])
        let sut = makeSUT(.kind(.provider(.googlePlay)))
        sut.chooseMethod(.googleSignIn)
        await sut.primaryAction()

        await sut.discard()

        XCTAssertEqual(auth.signOutCalls, ["user-1"])
    }
}
