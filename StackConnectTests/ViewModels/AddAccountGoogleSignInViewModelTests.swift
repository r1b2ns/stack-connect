import XCTest
import StackProtocols
@testable import StackConnect

/// Add Account with "Sign in with Google" (plan Phase 2): availability, the
/// sign-in states, the picker, every error of the plan and the analytics funnel.
@MainActor
final class AddAccountGoogleSignInViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private var auth: MockGoogleAuthService!
    private var resources: MockGoogleResourceListing!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        auth = MockGoogleAuthService()
        resources = MockGoogleResourceListing()
        suiteName = "AddAccountGoogleSignInViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.set(true, forKey: FeatureFlag.googleSignIn.rawValue)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        storage = nil
        keychain = nil
        analytics = nil
        auth = nil
        resources = nil
        defaults = nil
        try await super.tearDown()
    }

    private func makeSUT(_ provider: ProviderType) -> AddAccountViewModel {
        AddAccountViewModel(
            providerType: provider,
            storage: storage,
            keychain: keychain,
            googlePlayConnectionFactory: { _ in MockGooglePlayAccountConnection() },
            analytics: analytics,
            featureFlags: FeatureFlags(defaults: defaults),
            googleAuth: auth,
            googleResources: resources
        )
    }

    private let apps = [
        GoogleAccessibleResource(id: "com.a", title: "Alpha", subtitle: "com.a"),
        GoogleAccessibleResource(id: "com.b", title: "Beta", subtitle: "com.b")
    ]
    private let projects = [
        GoogleAccessibleResource(id: "alpha-1", title: "Alpha", subtitle: "alpha-1"),
        GoogleAccessibleResource(id: "beta-2", title: "Beta", subtitle: "beta-2")
    ]

    // MARK: - Availability (flag G9)

    func testGoogleSignInIsThePrimaryPathForPlayAndFirebase() {
        for provider in [ProviderType.googlePlay, .firebase] {
            let sut = makeSUT(provider)
            XCTAssertTrue(sut.uiState.isGoogleSignInAvailable, "\(provider)")
            XCTAssertEqual(sut.uiState.credentialMode, .googleSignIn)
            XCTAssertTrue(sut.uiState.isGoogleSignInMode)
            XCTAssertFalse(sut.uiState.canSave)
        }
    }

    func testFlagOffKeepsOnlyTheJSONForm() {
        defaults.set(false, forKey: FeatureFlag.googleSignIn.rawValue)

        let sut = makeSUT(.googlePlay)

        XCTAssertFalse(sut.uiState.isGoogleSignInAvailable)
        XCTAssertEqual(sut.uiState.credentialMode, .keyFile)
        sut.setCredentialMode(.googleSignIn)
        XCTAssertEqual(sut.uiState.credentialMode, .keyFile, "can't be entered while the flag is off")
    }

    func testFlagDefaultsOnInDebugBuilds() {
        #if DEBUG
        XCTAssertTrue(FeatureFlag.googleSignIn.defaultValue)
        #else
        XCTAssertFalse(FeatureFlag.googleSignIn.defaultValue)
        #endif
    }

    func testNotOfferedForAppStoreConnectOrAnUnconfiguredBuild() {
        XCTAssertFalse(makeSUT(.apple).uiState.isGoogleSignInAvailable)

        auth.isConfigured = false
        XCTAssertFalse(makeSUT(.firebase).uiState.isGoogleSignInAvailable)
    }

    func testSwitchingToTheJSONFormIsTracked() {
        let sut = makeSUT(.firebase)

        sut.setCredentialMode(.keyFile)

        XCTAssertEqual(sut.uiState.credentialMode, .keyFile)
        XCTAssertFalse(sut.uiState.isGoogleSignInMode)
        XCTAssertTrue(analytics.trackedEvents.contains(.buttonTap(.useServiceAccount, on: .addAccount)))
        sut.setCredentialMode(.googleSignIn)
        XCTAssertTrue(analytics.trackedEvents.contains(.buttonTap(.useGoogleSignIn, on: .addAccount)))
    }

    // MARK: - Sign-in → picker

    func testSignInListsPlayAppsPreselectedAndNamesTheAccountAfterTheEmail() async {
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.playAppsResult = .success(apps)
        let sut = makeSUT(.googlePlay)

        await sut.signInWithGoogle()

        XCTAssertEqual(auth.signInCalls, [GoogleOAuthScope.signIn])
        XCTAssertEqual(sut.uiState.google.step, .picking)
        XCTAssertEqual(sut.uiState.google.login?.email, "dev@example.com")
        XCTAssertEqual(sut.uiState.google.items.map(\.id), ["com.a", "com.b"])
        XCTAssertEqual(sut.uiState.google.selectedIds, ["com.a", "com.b"])
        XCTAssertEqual(sut.uiState.accountName, "dev@example.com")
        XCTAssertNil(sut.uiState.google.errorMessage)
        XCTAssertTrue(sut.uiState.canSave)
        XCTAssertEqual(analytics.results(of: .googleSignIn), [.success])
        XCTAssertEqual(analytics.actions(of: .googleSignInStarted).count, 1)
        XCTAssertEqual(analytics.actions(of: .googleSignIn).first?.parameters[AnalyticsParameterKey.missingScopeCount], .int(0))
    }

    func testSelectionTogglesAndSelectAll() async {
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.firebaseProjectsResult = .success(projects)
        let sut = makeSUT(.firebase)
        await sut.signInWithGoogle()

        sut.toggleGoogleItem("alpha-1")
        XCTAssertEqual(sut.uiState.google.selectedIds, ["beta-2"])
        XCTAssertFalse(sut.uiState.google.areAllSelected)

        sut.setAllGoogleItemsSelected(false)
        XCTAssertTrue(sut.uiState.google.selectedIds.isEmpty)
        XCTAssertFalse(sut.uiState.canSave)

        sut.setAllGoogleItemsSelected(true)
        XCTAssertTrue(sut.uiState.google.areAllSelected)
        sut.toggleGoogleItem("unknown")
        XCTAssertEqual(sut.uiState.google.selectedIds, ["alpha-1", "beta-2"])
    }

    // MARK: - Errors (plan Phase 2)

    func testCancelledSignInGoesBackToIdleAndIsTrackedAsCancelled() async {
        auth.signInResult = .failure(GoogleAuthError.cancelled)
        let sut = makeSUT(.firebase)

        await sut.signInWithGoogle()

        XCTAssertEqual(sut.uiState.google.step, .idle)
        XCTAssertNil(sut.uiState.google.errorMessage)
        XCTAssertNil(sut.uiState.google.login)
        XCTAssertEqual(analytics.results(of: .googleSignIn), [.cancelled])
    }

    func testBlockedAppOrNotATestUserShowsTheBlockedMessage() async {
        auth.signInResult = .failure(GoogleAuthError.accessDenied)
        let sut = makeSUT(.googlePlay)

        await sut.signInWithGoogle()

        XCTAssertEqual(sut.uiState.google.step, .idle)
        XCTAssertEqual(sut.uiState.google.errorMessage, GoogleAuthError.accessDenied.errorDescription)
        XCTAssertEqual(analytics.results(of: .googleSignIn), [.failure])
        XCTAssertEqual(analytics.actions(of: .googleSignIn).first?.parameters[AnalyticsParameterKey.errorCategory], .string("forbidden"))
    }

    func testUntickedOptionalScopeKeepsThePickerAndSaysWhichFeatureIsOff() async {
        auth.signInResult = .success(MockGoogleAuthService.result(missing: [GoogleOAuthScope.firebaseMessaging]))
        resources.firebaseProjectsResult = .success(projects)
        let sut = makeSUT(.firebase)

        await sut.signInWithGoogle()

        XCTAssertEqual(sut.uiState.google.step, .picking)
        XCTAssertEqual(sut.uiState.google.disabledFeatures, [.cloudMessaging])
        XCTAssertEqual(sut.uiState.google.missingScopes, [GoogleOAuthScope.firebaseMessaging])
        XCTAssertEqual(analytics.actions(of: .googleSignIn).first?.parameters[AnalyticsParameterKey.missingScopeCount], .int(1))
    }

    func testUntickedRequiredScopeBlocksThePickerUntilAccessIsGranted() async {
        auth.signInResult = .success(MockGoogleAuthService.result(missing: [GoogleOAuthScope.playDeveloperReporting, GoogleOAuthScope.firebase]))
        resources.playAppsResult = .success(apps)
        let sut = makeSUT(.googlePlay)

        await sut.signInWithGoogle()

        XCTAssertEqual(sut.uiState.google.step, .idle)
        XCTAssertNotNil(sut.uiState.google.login)
        XCTAssertEqual(sut.uiState.google.disabledFeatures, [.playApps], "only this provider's features are listed")
        XCTAssertNotNil(sut.uiState.google.errorMessage)
        XCTAssertFalse(sut.uiState.canSave)
        XCTAssertEqual(analytics.actions(of: .googleSignIn).first?.parameters[AnalyticsParameterKey.errorCategory], .string("scope_denied"))

        // Grant Access: one incremental request for the missing scope, then the list.
        auth.additionalScopesResult = .success(MockGoogleAuthService.result(isNewLogin: false))
        await sut.grantMissingGoogleAccess()

        XCTAssertEqual(auth.additionalScopesCalls.map(\.scopes), [[GoogleOAuthScope.playDeveloperReporting]])
        XCTAssertEqual(auth.additionalScopesCalls.map(\.loginId), ["user-1"])
        XCTAssertEqual(sut.uiState.google.step, .picking)
        XCTAssertTrue(sut.uiState.google.disabledFeatures.isEmpty)
        XCTAssertEqual(sut.uiState.google.items.count, 2)
        XCTAssertTrue(analytics.trackedEvents.contains(.buttonTap(.grantMissingAccess, on: .addAccount)))
    }

    func testServiceDisabledWhileListingShowsTheGenericMessage() async {
        let disabled = GoogleAuthError.http(statusCode: 403, summary: GoogleAPIErrorSummary(status: "PERMISSION_DENIED", reasons: ["SERVICE_DISABLED"]))
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.playAppsResult = .failure(disabled)
        let sut = makeSUT(.googlePlay)

        await sut.signInWithGoogle()

        XCTAssertEqual(sut.uiState.google.step, .idle)
        XCTAssertEqual(sut.uiState.google.errorMessage, String(localized: "Google couldn't complete the request right now. Try again later."))
        XCTAssertEqual(analytics.results(of: .load), [.failure])
        XCTAssertEqual(analytics.actions(of: .load).first?.parameters[AnalyticsParameterKey.errorCategory], .string("server"))
    }

    func testNothingVisibleSaysSo() async {
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.firebaseProjectsResult = .success([])
        let sut = makeSUT(.firebase)

        await sut.signInWithGoogle()

        XCTAssertEqual(sut.uiState.google.step, .picking)
        XCTAssertNotNil(sut.uiState.google.errorMessage)
        XCTAssertFalse(sut.uiState.canSave)
    }

    // MARK: - Signing in again (invalid_grant recovery, plan R5)

    func testSigningInAgainMarksWhatIsAlreadyAddedAndSaysItWorksAgain() async throws {
        let existing = AccountModel(name: "Alpha", providerType: .firebase, appsBundles: ["alpha-1"], authMethod: .googleSignIn)
        try await storage.save(existing, id: existing.id)
        keychain.setObject(FirebaseCredentials(googleLoginId: "user-1"), forKey: "credentials.\(existing.id)")
        auth.signInResult = .success(MockGoogleAuthService.result(isNewLogin: false))
        resources.firebaseProjectsResult = .success(projects)
        let sut = makeSUT(.firebase)

        await sut.signInWithGoogle()

        XCTAssertEqual(sut.uiState.google.items.map(\.isAlreadyAdded), [true, false])
        XCTAssertEqual(sut.uiState.google.selectedIds, ["beta-2"])
        XCTAssertNotNil(sut.uiState.google.notice)
        sut.toggleGoogleItem("alpha-1")
        XCTAssertEqual(sut.uiState.google.selectedIds, ["beta-2"], "an added project can't be selected")
    }

    // MARK: - Save

    func testSavingEveryPlayAppCreatesOneUnscopedAccountForTheLogin() async throws {
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.playAppsResult = .success(apps)
        let sut = makeSUT(.googlePlay)
        await sut.signInWithGoogle()

        await sut.save()

        XCTAssertTrue(sut.uiState.isSaved)
        let accounts = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(accounts.count, 1)
        let account = try XCTUnwrap(accounts.first)
        XCTAssertEqual(account.name, "dev@example.com")
        XCTAssertEqual(account.providerType, .googlePlay)
        XCTAssertEqual(account.authMethod, .googleSignIn)
        XCTAssertNil(account.appsBundles, "everything picked: apps added later show up too")
        XCTAssertFalse(account.isExportable)
        let credentials: GooglePlayCredentials? = keychain.object(forKey: "credentials.\(account.id)")
        XCTAssertEqual(credentials?.source, .googleSignIn(loginId: "user-1"))

        let created = try XCTUnwrap(analytics.actions(of: .createAccount).first)
        XCTAssertEqual(created.parameters[AnalyticsParameterKey.result], .string("success"))
        XCTAssertEqual(created.parameters[AnalyticsParameterKey.authMethod], .string("google_sign_in"))
        XCTAssertEqual(created.parameters[AnalyticsParameterKey.count], .int(1))
        XCTAssertEqual(created.parameters[AnalyticsParameterKey.kind], .string("googlePlay"))
    }

    func testSavingSomePlayAppsScopesTheAccount() async throws {
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.playAppsResult = .success(apps)
        let sut = makeSUT(.googlePlay)
        await sut.signInWithGoogle()
        sut.toggleGoogleItem("com.a")
        sut.uiState.googlePlayDeveloperId = "1234567890"

        await sut.save()

        let saved = try await storage.fetchAll(AccountModel.self)
        let account = try XCTUnwrap(saved.first)
        XCTAssertEqual(account.appsBundles, ["com.b"])
        XCTAssertEqual(account.googlePlayDeveloperId, "1234567890")
    }

    func testSecondPlayAccountForTheSameLoginIsADuplicate() async throws {
        let existing = AccountModel(name: "Mine", providerType: .googlePlay, appsBundles: ["com.a"], authMethod: .googleSignIn)
        try await storage.save(existing, id: existing.id)
        keychain.setObject(GooglePlayCredentials(googleLoginId: "user-1"), forKey: "credentials.\(existing.id)")
        auth.signInResult = .success(MockGoogleAuthService.result(isNewLogin: false))
        resources.playAppsResult = .success(apps)
        let sut = makeSUT(.googlePlay)
        await sut.signInWithGoogle()

        await sut.save()

        XCTAssertFalse(sut.uiState.isSaved)
        XCTAssertEqual(sut.uiState.validationError, String(localized: "This Google account is already added as \"Mine\"."))
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(analytics.actions(of: .createAccount).first?.parameters[AnalyticsParameterKey.errorCategory], .string("duplicate"))
    }

    func testSavingFirebaseProjectsCreatesOneAccountPerProject() async throws {
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.firebaseProjectsResult = .success(projects)
        let sut = makeSUT(.firebase)
        await sut.signInWithGoogle()

        await sut.save()

        XCTAssertTrue(sut.uiState.isSaved)
        let accounts = try await storage.fetchAll(AccountModel.self).sorted { $0.name < $1.name }
        XCTAssertEqual(accounts.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(accounts.map(\.appsBundles), [["alpha-1"], ["beta-2"]])
        XCTAssertEqual(accounts.map(\.authMethod), [.googleSignIn, .googleSignIn])
        for account in accounts {
            let credentials: FirebaseCredentials? = keychain.object(forKey: "credentials.\(account.id)")
            XCTAssertEqual(credentials?.source, .googleSignIn(loginId: "user-1"))
            XCTAssertTrue(account.allowsApp(bundleId: account.appsBundles?.first ?? ""))
            XCTAssertFalse(account.allowsApp(bundleId: "someone-elses-project"))
        }
        XCTAssertEqual(analytics.actions(of: .createAccount).first?.parameters[AnalyticsParameterKey.count], .int(2))
    }

    func testSaveWithNothingSelectedIsAValidationError() async throws {
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.firebaseProjectsResult = .success(projects)
        let sut = makeSUT(.firebase)
        await sut.signInWithGoogle()
        sut.setAllGoogleItemsSelected(false)

        await sut.save()

        XCTAssertFalse(sut.uiState.isSaved)
        XCTAssertEqual(sut.uiState.validationError, String(localized: "Select at least one project."))
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(keychain.storedKeys.isEmpty)
    }

    func testStorageFailureRollsTheCredentialsBack() async throws {
        auth.signInResult = .success(MockGoogleAuthService.result())
        resources.firebaseProjectsResult = .success([projects[0]])
        await storage.failSave(AccountModel.self)
        let sut = makeSUT(.firebase)
        await sut.signInWithGoogle()

        await sut.save()

        XCTAssertFalse(sut.uiState.isSaved)
        XCTAssertNotNil(sut.uiState.validationError)
        XCTAssertTrue(keychain.storedKeys.isEmpty)
        XCTAssertEqual(analytics.actions(of: .createAccount).first?.parameters[AnalyticsParameterKey.errorCategory], .string("storage"))
    }

    // MARK: - Closing without saving

    func testClosingWithoutSavingSignsOutANewUnusedLogin() async {
        auth.signInResult = .success(MockGoogleAuthService.result(isNewLogin: true))
        resources.firebaseProjectsResult = .success(projects)
        let sut = makeSUT(.firebase)
        await sut.signInWithGoogle()

        await sut.discardUnsavedGoogleLogin()

        XCTAssertEqual(auth.signOutCalls, ["user-1"])
    }

    func testClosingKeepsALoginThatWasAlreadyOnTheDevice() async {
        auth.signInResult = .success(MockGoogleAuthService.result(isNewLogin: false))
        resources.firebaseProjectsResult = .success(projects)
        let sut = makeSUT(.firebase)
        await sut.signInWithGoogle()

        await sut.discardUnsavedGoogleLogin()

        XCTAssertEqual(auth.signOutCalls, [])
    }

    func testClosingAfterSavingKeepsTheLogin() async {
        auth.signInResult = .success(MockGoogleAuthService.result(isNewLogin: true))
        resources.firebaseProjectsResult = .success(projects)
        let sut = makeSUT(.firebase)
        await sut.signInWithGoogle()
        await sut.save()

        await sut.discardUnsavedGoogleLogin()

        XCTAssertEqual(auth.signOutCalls, [])
    }
}
