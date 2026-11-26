import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// "Sign in with Apple ID" (plan `apple-id-sign-in.md` Phase 3): every step
/// of the core's sign-in, the wrong password and code, the SMS fallback, the
/// team picker, the acknowledgement, signing in again and the analytics.
@MainActor
final class AppleIdSignInViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private var status: MockAppleSessionStatus!
    private var roles: MockAppleSessionRoleResolver!
    private var flow: MockAppleIdSignIn!
    private var savedSessionsPassed: [Data?] = []

    private let appleId = "dev@example.com"
    private let blob = Data("session-blob".utf8)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        status = MockAppleSessionStatus()
        roles = MockAppleSessionRoleResolver()
        flow = MockAppleIdSignIn()
        savedSessionsPassed = []
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        analytics = nil
        status = nil
        roles = nil
        flow = nil
        try await super.tearDown()
    }

    private func makeSUT(_ mode: AppleIdSignInMode = .addAccounts) -> AppleIdSignInViewModel {
        AppleIdSignInViewModel(
            mode: mode,
            storage: storage,
            keychain: keychain,
            sessionStatus: status,
            roleResolver: roles,
            analytics: analytics,
            makeSignIn: { [unowned self] saved in
                self.savedSessionsPassed.append(saved)
                return self.flow
            }
        )
    }

    private func needsCode(
        codeLength: UInt8 = 6,
        delivery: AppleCodeDelivery = .trustedDevices,
        phones: [AppleTrustedPhone] = [.fixture]
    ) -> AppleSignInStep {
        .needsCode(methods: [.trustedDevice, .phone(phoneId: AppleTrustedPhone.fixture.id)], phones: phones, codeLength: codeLength, delivery: delivery)
    }

    private func signedInSUT(teams: [AppleTeam], mode: AppleIdSignInMode = .addAccounts) async -> AppleIdSignInViewModel {
        flow.startResults = [.success(.done(teams: teams))]
        let sut = makeSUT(mode)
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        await sut.signIn()
        return sut
    }

    private func actions(_ name: AnalyticsAction) -> [AnalyticsEvent] {
        analytics.trackedEvents.filter { $0.parameters[AnalyticsParameterKey.actionName] == .string(name.rawValue) }
    }

    private func savedAccounts() async throws -> [AccountModel] {
        try await storage.fetchAll(AccountModel.self)
    }

    // MARK: - Screen 1

    func testStartsOnTheCredentialsScreen() {
        let sut = makeSUT()

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertTrue(sut.uiState.isEmailEditable)
        XCTAssertFalse(sut.uiState.canSignIn)
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        XCTAssertTrue(sut.uiState.canSignIn)
    }

    func testNeedsCodeShowsTheCodeScreenAndClearsThePassword() async {
        flow.startResults = [.success(needsCode())]
        let sut = makeSUT()
        sut.uiState.email = "  Dev@Example.com "
        sut.uiState.password = "secret"

        await sut.signIn()

        XCTAssertEqual(flow.starts, [.init(email: "Dev@Example.com", password: "secret")], "the password goes to the core once")
        XCTAssertEqual(sut.uiState.password, "", "never kept after the call")
        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertEqual(sut.uiState.codeLength, 6)
        XCTAssertEqual(sut.uiState.codeMethod, .trustedDevice)
        XCTAssertEqual(sut.uiState.phones, [.fixture])
        XCTAssertEqual(actions(.appleIdSignInStarted).count, 1)
        XCTAssertNil(savedSessionsPassed.first ?? nil, "a new sign-in starts without a saved session")
    }

    func testCodeLengthComesFromTheCore() async {
        flow.startResults = [.success(needsCode(codeLength: 8))]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"

        await sut.signIn()

        XCTAssertEqual(sut.uiState.codeLength, 8)
    }

    func testWrongPasswordStaysOnTheCredentialsScreen() async {
        flow.startResults = [.failure(StackError.InvalidCredentials(message: "bad"))]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "wrong"

        await sut.signIn()

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.uiState.password, "", "cleared even when Apple refuses it")
        XCTAssertEqual(sut.uiState.errorMessage, String(localized: "The Apple ID or password is incorrect."))
        let failure = actions(.appleIdSignIn).last
        XCTAssertEqual(failure?.parameters[AnalyticsParameterKey.result], .string("failure"))
        XCTAssertEqual(failure?.parameters[AnalyticsParameterKey.errorCategory], .string("invalid_credentials"))
    }

    func testEmptyPasswordIsRefusedLocally() async {
        let sut = makeSUT()
        sut.uiState.email = appleId

        await sut.signIn()

        XCTAssertTrue(flow.starts.isEmpty)
        XCTAssertEqual(sut.uiState.errorMessage, String(localized: "Enter your Apple ID and password."))
    }

    func testErrorCategoriesHaveTheirOwnCopy() async {
        let cases: [(Error, String, String)] = [
            (StackError.Network(message: "offline"), String(localized: "Couldn't reach Apple. Check your connection and try again."), "network"),
            (StackError.Http(status: 503, message: ""), String(localized: "Apple's sign-in service isn't responding. Try again later."), "server"),
            (StackError.Http(status: 429, message: ""), String(localized: "Apple is limiting sign-in attempts. Wait a few minutes and try again."), "unknown"),
            (StackError.Decode(message: "x"), String(localized: "Apple returned an unexpected response. Try again later."), "server")
        ]
        for (error, message, category) in cases {
            flow.startResults = [.failure(error)]
            let sut = makeSUT()
            sut.uiState.email = appleId
            sut.uiState.password = "secret"

            await sut.signIn()

            XCTAssertEqual(sut.uiState.errorMessage, message, "\(error)")
            XCTAssertEqual(actions(.appleIdSignIn).last?.parameters[AnalyticsParameterKey.errorCategory], .string(category), "\(error)")
        }
    }

    func testAuthErrorKeepsTheCoreCause() async {
        flow.startResults = [.failure(StackError.Auth(message: "This Apple ID uses a security key."))]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"

        await sut.signIn()

        XCTAssertEqual(sut.uiState.errorMessage, "\(String(localized: "Apple didn't complete the sign-in."))\nThis Apple ID uses a security key.")
    }

    // MARK: - Screen 2

    func testCompleteCodeIsSubmittedToTheTrustedDevices() async {
        flow.startResults = [.success(needsCode())]
        flow.submitResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        await sut.signIn()

        await sut.updateCode("12a 34")
        XCTAssertEqual(sut.uiState.code, "1234", "digits only")
        XCTAssertTrue(flow.submittedCodes.isEmpty, "not complete yet")
        await sut.updateCode("1234567890")

        XCTAssertEqual(flow.submittedCodes.map(\.code), ["123456"])
        XCTAssertEqual(flow.submittedCodes.first?.method, .trustedDevice)
        XCTAssertEqual(sut.uiState.step, .teams)
    }

    func testWrongCodeStaysOnTheCodeScreen() async {
        flow.startResults = [.success(needsCode())]
        flow.submitResults = [
            .failure(StackError.InvalidCredentials(message: "wrong code")),
            .success(.done(teams: [.fixture(1, "Alpha")]))
        ]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        await sut.signIn()

        await sut.updateCode("000000")

        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertEqual(sut.uiState.code, "")
        XCTAssertEqual(sut.uiState.codeError, String(localized: "That code isn't right. Check it and try again."))
        XCTAssertNil(sut.uiState.errorMessage)

        await sut.updateCode("123456")

        XCTAssertNil(sut.uiState.codeError)
        XCTAssertEqual(sut.uiState.step, .teams, "the same sign-in accepts the next code")
        XCTAssertEqual(flow.starts.count, 1)
    }

    func testSmsFallbackSendsTheCodeToThatPhone() async {
        flow.startResults = [.success(needsCode())]
        flow.smsResults = [.success(needsCode(delivery: .phone(phoneId: 7)))]
        flow.submitResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        await sut.signIn()

        await sut.requestSms(phoneId: 7)

        XCTAssertEqual(flow.requestedSmsPhoneIds, [7])
        XCTAssertEqual(sut.uiState.codeMethod, .phone(phoneId: 7))
        XCTAssertEqual(sut.uiState.notice, String(localized: "Enter the code sent to \(AppleTrustedPhone.fixture.maskedNumber)."))
        XCTAssertEqual(actions(.appleIdCodeRequested).last?.parameters[AnalyticsParameterKey.result], .string("success"))

        await sut.updateCode("654321")

        XCTAssertEqual(flow.submittedCodes.first?.method, .phone(phoneId: 7))
        XCTAssertEqual(sut.uiState.step, .teams)
    }

    func testFailedSmsRequestStaysOnTheCodeScreen() async {
        flow.startResults = [.success(needsCode())]
        flow.smsResults = [.failure(StackError.Http(status: 429, message: ""))]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        await sut.signIn()

        await sut.requestSms(phoneId: 7)

        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertNotNil(sut.uiState.errorMessage)
        XCTAssertEqual(actions(.appleIdCodeRequested).last?.parameters[AnalyticsParameterKey.result], .string("failure"))
    }

    func testCodeNotSentWaitsForASmsRequest() async {
        flow.startResults = [.success(.needsCode(methods: [.phone(phoneId: 7)], phones: [.fixture], codeLength: 6, delivery: .notSent))]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"

        await sut.signIn()

        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertNil(sut.uiState.codeMethod)
        sut.uiState.code = "123456"
        XCTAssertFalse(sut.uiState.canSubmitCode, "nowhere to verify the code against yet")
    }

    func testStartOverGoesBackToTheCredentials() async {
        flow.startResults = [.success(needsCode())]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        await sut.signIn()

        sut.startOver()

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.uiState.email, appleId)
        XCTAssertNil(sut.uiState.codeMethod)
    }

    // MARK: - Needs acknowledgement

    func testNeedsAcknowledgementExplainsWhatToDo() async {
        flow.startResults = [.success(.needsAcknowledgement)]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"

        await sut.signIn()

        XCTAssertEqual(sut.uiState.step, .needsAcknowledgement)
        XCTAssertEqual(sut.openAppleIdWebsite(), URL(string: "https://appleid.apple.com"))
        XCTAssertEqual(actions(.appleIdSignIn).last?.parameters[AnalyticsParameterKey.errorCategory], .string("forbidden"))
        XCTAssertTrue(keychain.storedKeys.isEmpty, "nothing stored")

        sut.startOver()
        XCTAssertEqual(sut.uiState.step, .credentials)
    }

    // MARK: - Screen 3

    func testDoneListsEveryTeamSelected() async {
        let sut = await signedInSUT(teams: [.fixture(1, "Alpha"), .fixture(2, "Beta")])

        XCTAssertEqual(sut.uiState.step, .teams)
        XCTAssertEqual(sut.uiState.teams.map(\.id), [1, 2])
        XCTAssertEqual(sut.uiState.selectedTeamIds, [1, 2])
        XCTAssertTrue(sut.uiState.canSave)
        let success = actions(.appleIdSignIn).last
        XCTAssertEqual(success?.parameters[AnalyticsParameterKey.result], .string("success"))
        XCTAssertEqual(success?.parameters[AnalyticsParameterKey.count], .int(2))
        XCTAssertEqual(flow.finishCount, 0, "the session is taken only on save")
    }

    func testSavingOneTeamAddsOneSessionAccount() async throws {
        roles.roles = [1: .admin]
        let sut = await signedInSUT(teams: [.fixture(1, "Alpha"), .fixture(2, "Beta")])
        sut.toggleTeam(2)

        await sut.save()

        let accounts = try await savedAccounts()
        XCTAssertEqual(accounts.count, 1)
        let account = try XCTUnwrap(accounts.first)
        XCTAssertEqual(account.name, "Alpha")
        XCTAssertEqual(account.authMethod, .appleIdSignIn)
        XCTAssertEqual(account.role, .admin, "derived from the user's App Store Connect roles")
        let credentials: AppleCredentials = try XCTUnwrap(keychain.object(forKey: "credentials.\(account.id)"))
        XCTAssertEqual(credentials.source, .webSession(AppleWebSessionReference(appleId: appleId, teamId: 1, teamName: "Alpha")))
        XCTAssertTrue(credentials.privateKey.isEmpty)
        XCTAssertEqual(keychain.data(forKey: "appleSession.\(appleId)"), blob)
        XCTAssertEqual(status.markedValid, [appleId])
        XCTAssertEqual(sut.uiState.step, .finished)
        let create = actions(.createAccount).last
        XCTAssertEqual(create?.parameters[AnalyticsParameterKey.authMethod], .string("apple_id_sign_in"))
        XCTAssertEqual(create?.parameters[AnalyticsParameterKey.count], .int(1))
        XCTAssertEqual(create?.parameters[AnalyticsParameterKey.result], .string("success"))
    }

    func testSavingSeveralTeamsSharesOneSession() async throws {
        let sut = await signedInSUT(teams: [.fixture(1, "Alpha"), .fixture(2, "Beta")])

        await sut.save()

        let accounts = try await savedAccounts()
        XCTAssertEqual(Set(accounts.map(\.name)), ["Alpha", "Beta"])
        let references = accounts.compactMap { AppleSessionReferences.reference(of: $0, keychain: keychain) }
        XCTAssertEqual(Set(references.map(\.teamId)), [1, 2])
        XCTAssertEqual(Set(references.map(\.appleId)), [appleId])
        XCTAssertEqual(keychain.storedKeys.filter { $0.hasPrefix("appleSession.") }, ["appleSession.\(appleId)"], "one session item")
        XCTAssertEqual(flow.finishCount, 1)
    }

    func testTeamsAlreadyAddedAreMarkedAndNotAddedAgain() async throws {
        let existing = AccountModel(name: "Alpha", providerType: .apple, authMethod: .appleIdSignIn)
        try await storage.save(existing, id: existing.id)
        keychain.setObject(AppleCredentials(webSession: .init(appleId: appleId, teamId: 1, teamName: "Alpha")), forKey: "credentials.\(existing.id)")

        let sut = await signedInSUT(teams: [.fixture(1, "Alpha"), .fixture(2, "Beta")])

        XCTAssertEqual(sut.uiState.teams.map(\.isAlreadyAdded), [true, false])
        XCTAssertEqual(sut.uiState.selectedTeamIds, [2])
        XCTAssertNotNil(sut.uiState.notice)
        sut.toggleTeam(1)
        XCTAssertEqual(sut.uiState.selectedTeamIds, [2], "an added team can't be selected")

        await sut.save()

        let count = try await savedAccounts().count
        XCTAssertEqual(count, 2)
    }

    func testEveryTeamAddedOnlyRenewsTheSession() async throws {
        let existing = AccountModel(name: "Alpha", providerType: .apple, authMethod: .appleIdSignIn)
        try await storage.save(existing, id: existing.id)
        keychain.setObject(AppleCredentials(webSession: .init(appleId: appleId, teamId: 1, teamName: "Alpha")), forKey: "credentials.\(existing.id)")
        let sut = await signedInSUT(teams: [.fixture(1, "Alpha")])

        XCTAssertTrue(sut.uiState.canSave)
        await sut.save()

        let count = try await savedAccounts().count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(keychain.data(forKey: "appleSession.\(appleId)"), blob)
        XCTAssertEqual(sut.uiState.step, .finished)
    }

    func testDeselectingEveryTeamDisablesSave() async {
        let sut = await signedInSUT(teams: [.fixture(1, "Alpha"), .fixture(2, "Beta")])

        sut.setAllTeamsSelected(false)

        XCTAssertFalse(sut.uiState.canSave)
        sut.setAllTeamsSelected(true)
        XCTAssertEqual(sut.uiState.selectedTeamIds, [1, 2])
    }

    func testNoTeamsShowsAnError() async {
        let sut = await signedInSUT(teams: [])

        XCTAssertEqual(sut.uiState.errorMessage, String(localized: "This Apple ID isn't a member of any App Store Connect team."))
        XCTAssertFalse(sut.uiState.canSave)
    }

    func testFailedFinishSavesNothing() async throws {
        flow.finishResult = .failure(StackError.Auth(message: "not signed in"))
        let sut = await signedInSUT(teams: [.fixture(1, "Alpha")])

        await sut.save()

        let accounts = try await savedAccounts()
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertTrue(keychain.storedKeys.isEmpty)
        XCTAssertEqual(sut.uiState.step, .teams)
        XCTAssertEqual(actions(.createAccount).last?.parameters[AnalyticsParameterKey.result], .string("failure"))
    }

    // MARK: - Sign in again (expired session)

    func testSignInAgainKeepsTheAppleIdAndReplacesTheSession() async throws {
        let oldBlob = Data("old".utf8)
        keychain.set(oldBlob, forKey: "appleSession.\(appleId)")
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        flow.finishResult = .success(blob)
        let sut = makeSUT(.signInAgain(appleId: appleId))

        XCTAssertEqual(sut.uiState.email, appleId)
        XCTAssertFalse(sut.uiState.isEmailEditable)
        sut.uiState.password = "secret"
        await sut.signIn()

        XCTAssertEqual(savedSessionsPassed, [oldBlob], "the saved session's trust cookie can spare the code")
        XCTAssertEqual(keychain.data(forKey: "appleSession.\(appleId)"), blob)
        XCTAssertEqual(status.markedValid, [appleId])
        XCTAssertEqual(sut.uiState.step, .finished, "no team picker")
        let accounts = try await savedAccounts()
        XCTAssertTrue(accounts.isEmpty, "no account added")
        XCTAssertEqual(actions(.appleIdSignInStarted).last?.parameters[AnalyticsParameterKey.trigger], .string("sign_in_again"))
    }

    // MARK: - Saved password

    private var passwordKey: String { "applePassword.\(appleId)" }

    private func taps(_ button: AnalyticsButton) -> [AnalyticsEvent] {
        analytics.trackedEvents.filter { $0.parameters[AnalyticsParameterKey.buttonName] == .string(button.rawValue) }
    }

    func testPasswordIsSavedOnlyOnceTheSignInFinished() async {
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT()
        sut.setSavesPassword(true)
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        await sut.signIn()

        XCTAssertNil(keychain.string(forKey: passwordKey), "not before Apple accepted it and the session was taken")

        await sut.save()

        XCTAssertEqual(keychain.string(forKey: passwordKey), "secret")
        XCTAssertEqual(sut.uiState.password, "", "the state never keeps it")
    }

    func testPasswordIsNotSavedWhenFinishFails() async {
        flow.finishResult = .failure(StackError.Auth(message: "not signed in"))
        let sut = await signedInSUT(teams: [.fixture(1, "Alpha")])

        await sut.save()

        XCTAssertNil(keychain.string(forKey: passwordKey))
    }

    func testPasswordIsNotSavedWhileWaitingForTheCode() async {
        flow.startResults = [.success(needsCode())]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"

        await sut.signIn()
        sut.discard()

        XCTAssertNil(keychain.string(forKey: passwordKey))
    }

    func testPasswordIsNotSavedWhenAppleRefusesIt() async {
        flow.startResults = [.failure(StackError.InvalidCredentials(message: "the Apple ID or password is incorrect"))]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "wrong"

        await sut.signIn()

        XCTAssertTrue(keychain.storedKeys.isEmpty)
    }

    func testSignInAgainWithASavedPasswordGoesStraightToTheCode() async {
        keychain.set("saved", forKey: passwordKey)
        flow.startResults = [.success(needsCode())]
        let sut = makeSUT(.signInAgain(appleId: appleId))

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertEqual(flow.starts, [.init(email: appleId, password: "saved")])
        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertTrue(sut.uiState.usesSavedPassword)
        XCTAssertFalse(sut.uiState.isEmailEditable, "the Apple ID stays read-only")
        XCTAssertEqual(sut.uiState.password, "")
        XCTAssertTrue(taps(.signInWithAppleId).isEmpty, "not a tap: started on its own")
        XCTAssertEqual(actions(.appleIdSignInStarted).count, 1)
    }

    func testSignInAgainWithASavedPasswordRunsOnce() async {
        keychain.set("saved", forKey: passwordKey)
        flow.startResults = [.success(needsCode())]
        let sut = makeSUT(.signInAgain(appleId: appleId))

        await sut.signInWithSavedPasswordIfAvailable()
        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertEqual(flow.starts.count, 1, "the screen appearing again doesn't restart it")
    }

    func testSignInAgainWithASavedPasswordAndTrustedSessionFinishesAndRefreshesIt() async {
        keychain.set("saved", forKey: passwordKey)
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT(.signInAgain(appleId: appleId))

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved")
        XCTAssertEqual(keychain.data(forKey: "appleSession.\(appleId)"), blob)
    }

    func testSignInAgainWithoutASavedPasswordAsksForIt() async {
        let sut = makeSUT(.signInAgain(appleId: appleId))

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertTrue(flow.starts.isEmpty)
        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertFalse(sut.uiState.usesSavedPassword)
        XCTAssertFalse(sut.uiState.canSignIn, "a password is needed")
    }

    func testRefusedSavedPasswordIsDeletedAndThePasswordIsAskedFor() async {
        keychain.set("old", forKey: passwordKey)
        flow.startResults = [.failure(StackError.InvalidCredentials(message: "the Apple ID or password is incorrect"))]
        let sut = makeSUT(.signInAgain(appleId: appleId))

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertNil(keychain.string(forKey: passwordKey), "a changed password is forgotten")
        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertFalse(sut.uiState.usesSavedPassword, "the password field is back")
        XCTAssertNil(sut.uiState.errorMessage)
        XCTAssertEqual(sut.uiState.notice, String(localized: "The saved password didn't work. It may have changed: enter your current Apple ID password."))
        XCTAssertEqual(actions(.appleIdSignIn).last?.parameters[AnalyticsParameterKey.errorCategory], .string("invalid_credentials"))
    }

    func testNewPasswordAfterARefusedSavedOneIsSaved() async {
        keychain.set("old", forKey: passwordKey)
        flow.startResults = [
            .failure(StackError.InvalidCredentials(message: "the Apple ID or password is incorrect")),
            .success(.done(teams: [.fixture(1, "Alpha")]))
        ]
        let sut = makeSUT(.signInAgain(appleId: appleId))
        await sut.signInWithSavedPasswordIfAvailable()

        sut.uiState.password = "new"
        await sut.signIn()

        XCTAssertEqual(flow.starts.map(\.password), ["old", "new"])
        XCTAssertNil(sut.uiState.notice)
        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "new")
    }

    func testOtherFailuresWithTheSavedPasswordKeepIt() async {
        keychain.set("saved", forKey: passwordKey)
        flow.startResults = [.failure(StackError.Network(message: "offline"))]
        let sut = makeSUT(.signInAgain(appleId: appleId))

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved", "only a refused password is removed")
        XCTAssertTrue(sut.uiState.usesSavedPassword, "Continue retries with it")
        XCTAssertTrue(sut.uiState.canSignIn)
        XCTAssertEqual(sut.uiState.errorMessage, String(localized: "Couldn't reach Apple. Check your connection and try again."))
    }

    /// 429, every 5xx and network failures: only the error shows; the saved
    /// password stays saved and in use, so the retry doesn't ask for it.
    func testTransientFailuresWithTheSavedPasswordKeepItInUse() async {
        let unavailable = String(localized: "Apple's sign-in service isn't responding. Try again later.")
        let offline = String(localized: "Couldn't reach Apple. Check your connection and try again.")
        let cases: [(String, Error, String)] = [
            ("429", StackError.Http(status: 429, message: "Too Many Requests"),
             String(localized: "Apple is limiting sign-in attempts. Wait a few minutes and try again.")),
            ("500", StackError.Http(status: 500, message: "Internal Server Error"), unavailable),
            ("502", StackError.Http(status: 502, message: "Bad Gateway"), unavailable),
            ("503", StackError.Http(status: 503, message: "Apple's sign-in service is unavailable (HTTP 503); try again later"), unavailable),
            ("network", StackError.Network(message: "offline"), offline),
            ("offline", OfflineError.noConnection, offline),
            ("timeout", URLError(.timedOut), offline)
        ]
        for (name, error, message) in cases {
            keychain = MockKeyStorable()
            keychain.set("saved", forKey: passwordKey)
            flow = MockAppleIdSignIn()
            flow.startResults = [.failure(error), .success(needsCode())]
            let sut = makeSUT(.signInAgain(appleId: appleId))

            await sut.signInWithSavedPasswordIfAvailable()

            XCTAssertEqual(keychain.string(forKey: passwordKey), "saved", "\(name): only a refused password is removed")
            XCTAssertEqual(sut.uiState.step, .credentials, name)
            XCTAssertTrue(sut.uiState.usesSavedPassword, "\(name): never back to the password field")
            XCTAssertTrue(sut.uiState.canSignIn, "\(name): the retry needs no typing")
            XCTAssertEqual(sut.uiState.errorMessage, message, name)

            // The screen appearing again (wizard step change) keeps it too.
            sut.emailDidChange()
            XCTAssertTrue(sut.uiState.usesSavedPassword, name)

            await sut.signIn()

            XCTAssertEqual(flow.starts.map(\.password), ["saved", "saved"], "\(name): the retry uses the saved password")
            XCTAssertEqual(sut.uiState.step, .code, name)
        }
    }

    func testWrongCodeWithTheSavedPasswordKeepsIt() async {
        keychain.set("saved", forKey: passwordKey)
        flow.startResults = [.success(needsCode())]
        flow.submitResults = [.failure(StackError.InvalidCredentials(message: "the verification code is incorrect"))]
        let sut = makeSUT(.signInAgain(appleId: appleId))
        await sut.signInWithSavedPasswordIfAvailable()

        await sut.updateCode("000000")

        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertNotNil(sut.uiState.codeError)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved", "a wrong code says nothing about the password")
    }

    func testUseDifferentPasswordFromTheCodeGoesBackToThePasswordField() async {
        keychain.set("saved", forKey: passwordKey)
        flow.startResults = [.success(needsCode()), .success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT(.signInAgain(appleId: appleId))
        await sut.signInWithSavedPasswordIfAvailable()

        sut.useDifferentPassword()

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertFalse(sut.uiState.usesSavedPassword)
        XCTAssertNil(sut.uiState.codeMethod)
        XCTAssertEqual(taps(.useDifferentPassword).count, 1)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved", "kept until a sign-in replaces it")

        sut.uiState.password = "typed"
        await sut.signIn()

        XCTAssertEqual(flow.starts.map(\.password), ["saved", "typed"])
        XCTAssertEqual(keychain.string(forKey: passwordKey), "typed", "refreshed by the successful sign-in")
    }

    func testWrongTypedPasswordKeepsTheSavedOne() async {
        keychain.set("saved", forKey: passwordKey)
        let sut = makeSUT(.signInAgain(appleId: appleId))
        flow.startResults = [.success(needsCode())]
        await sut.signInWithSavedPasswordIfAvailable()
        sut.useDifferentPassword()
        flow.startResults = [.failure(StackError.InvalidCredentials(message: "the Apple ID or password is incorrect"))]

        sut.uiState.password = "typo"
        await sut.signIn()

        XCTAssertEqual(sut.uiState.errorMessage, String(localized: "The Apple ID or password is incorrect."))
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved", "only the saved password being refused removes it")
    }

    func testAddAccountOffersTheSavedPasswordOfAKnownAppleId() async {
        keychain.set("saved", forKey: passwordKey)
        flow.startResults = [.success(needsCode())]
        let sut = makeSUT()
        await sut.signInWithSavedPasswordIfAvailable()
        XCTAssertTrue(flow.starts.isEmpty, "Add Account never starts on its own")

        sut.uiState.email = "other@example.com"
        sut.emailDidChange()
        XCTAssertFalse(sut.uiState.usesSavedPassword)

        sut.uiState.email = "Dev@Example.com"
        sut.emailDidChange()
        XCTAssertTrue(sut.uiState.usesSavedPassword)
        XCTAssertTrue(sut.uiState.canSignIn, "no password to type")

        await sut.signIn()

        XCTAssertEqual(flow.starts, [.init(email: "Dev@Example.com", password: "saved")])
        XCTAssertEqual(sut.uiState.step, .code)
    }

    func testDeclinedSavedPasswordIsNotOfferedAgainForThatAppleId() {
        keychain.set("saved", forKey: passwordKey)
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.emailDidChange()

        sut.useDifferentPassword()
        sut.uiState.email = appleId + " "
        sut.emailDidChange()

        XCTAssertFalse(sut.uiState.usesSavedPassword)
        XCTAssertFalse(sut.uiState.canSignIn)
    }

    // MARK: - Save password on this device

    func testSavePasswordIsOffByDefault() {
        XCTAssertFalse(makeSUT().uiState.savesPassword)
        XCTAssertFalse(makeSUT(.signInAgain(appleId: appleId)).uiState.savesPassword,
                       "no password saved for the Apple ID")
    }

    func testSavePasswordStartsOnWhenSigningInAgainWithASavedPassword() {
        keychain.set("saved", forKey: passwordKey)

        XCTAssertTrue(makeSUT(.signInAgain(appleId: appleId)).uiState.savesPassword)
    }

    func testFreshSignInWithTheToggleUntouchedDoesNotSaveThePassword() async {
        let sut = makeSUT()
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        sut.uiState.email = appleId
        sut.emailDidChange()
        sut.uiState.password = "secret"
        await sut.signIn()

        await sut.save()

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertNil(keychain.string(forKey: passwordKey))
        XCTAssertEqual(keychain.data(forKey: "appleSession.\(appleId)"), blob, "the session is still kept")
    }

    func testFreshSignInAgainWithoutASavedPasswordDoesNotSaveIt() async {
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT(.signInAgain(appleId: appleId))
        await sut.signInWithSavedPasswordIfAvailable()
        XCTAssertFalse(sut.uiState.usesSavedPassword)
        XCTAssertFalse(sut.uiState.savesPassword)

        sut.uiState.password = "secret"
        await sut.signIn()

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertNil(keychain.string(forKey: passwordKey))
    }

    func testSavePasswordDefaultFollowsTheAppleIdUntilToggled() {
        keychain.set("saved", forKey: passwordKey)
        let sut = makeSUT()

        sut.uiState.email = appleId
        sut.emailDidChange()
        XCTAssertTrue(sut.uiState.savesPassword, "a password is saved for this Apple ID")

        sut.uiState.email = "other@example.com"
        sut.emailDidChange()
        XCTAssertFalse(sut.uiState.savesPassword, "back to off: nothing saved for this one")

        sut.uiState.email = appleId
        sut.emailDidChange()
        XCTAssertTrue(sut.uiState.savesPassword)
        XCTAssertTrue(taps(.savePasswordOn).isEmpty && taps(.savePasswordOff).isEmpty, "defaults aren't taps")
    }

    func testSavePasswordOnSurvivesSwitchingToAnAppleIdWithoutASavedPassword() {
        let sut = makeSUT()
        sut.setSavesPassword(true)

        sut.uiState.email = appleId
        sut.emailDidChange()
        sut.uiState.email = "other@example.com"
        sut.emailDidChange()

        XCTAssertTrue(sut.uiState.savesPassword)
    }

    func testSavePasswordStartsOnWhenAPasswordIsAlreadySaved() {
        keychain.set("saved", forKey: passwordKey)
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.emailDidChange()

        sut.useDifferentPassword()

        XCTAssertFalse(sut.uiState.usesSavedPassword, "the password field and the toggle are back")
        XCTAssertTrue(sut.uiState.savesPassword)
    }

    func testSavePasswordOnSavesThePasswordOnceSignedIn() async {
        let sut = makeSUT()
        sut.setSavesPassword(false)
        sut.setSavesPassword(true)
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        await sut.signIn()

        await sut.save()

        XCTAssertEqual(keychain.string(forKey: passwordKey), "secret")
    }

    func testSavePasswordOffDoesNotSaveThePassword() async {
        let sut = makeSUT()
        sut.setSavesPassword(false)
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        await sut.signIn()

        await sut.save()

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertNil(keychain.string(forKey: passwordKey))
        XCTAssertEqual(keychain.data(forKey: "appleSession.\(appleId)"), blob, "the session is still kept")
    }

    func testSavePasswordOffDeletesThePasswordSavedEarlierOnceSignedIn() async {
        keychain.set("saved", forKey: passwordKey)
        flow.startResults = [.success(needsCode())]
        let sut = makeSUT(.signInAgain(appleId: appleId))
        await sut.signInWithSavedPasswordIfAvailable()
        sut.useDifferentPassword()
        sut.setSavesPassword(false)
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]

        sut.uiState.password = "typed"
        await sut.signIn()

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertNil(keychain.string(forKey: passwordKey), "removed once Apple accepted the sign-in")
    }

    func testSavePasswordOffKeepsTheSavedPasswordUntilSignedIn() async {
        keychain.set("saved", forKey: passwordKey)
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.emailDidChange()
        sut.useDifferentPassword()
        sut.setSavesPassword(false)
        flow.startResults = [.success(needsCode())]

        sut.uiState.password = "typed"
        await sut.signIn()

        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved", "nothing changes before the sign-in finished")
    }

    func testSavePasswordOffDeletesTheSavedPasswordInUseOnceSignedIn() async {
        keychain.set("saved", forKey: passwordKey)
        let sut = makeSUT()
        sut.setSavesPassword(false)
        sut.uiState.email = appleId
        sut.emailDidChange()
        XCTAssertTrue(sut.uiState.usesSavedPassword)
        XCTAssertFalse(sut.uiState.savesPassword, "the saved-password row doesn't reset the off")
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]

        await sut.signIn()
        XCTAssertEqual(flow.starts.map(\.password), ["saved"], "the saved password is still used to sign in")
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved", "nothing changes before the sign-in finished")

        await sut.save()

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertNil(keychain.string(forKey: passwordKey), "an explicit off is honored")
        XCTAssertEqual(keychain.data(forKey: "appleSession.\(appleId)"), blob, "the session is still kept")
    }

    func testSavePasswordOffSurvivesTheSavedPasswordRowComingAndGoing() {
        keychain.set("saved", forKey: passwordKey)
        let sut = makeSUT()
        sut.setSavesPassword(false)

        sut.uiState.email = appleId
        sut.emailDidChange()
        XCTAssertTrue(sut.uiState.usesSavedPassword)
        sut.uiState.email = "other@example.com"
        sut.emailDidChange()
        XCTAssertFalse(sut.uiState.usesSavedPassword)
        sut.uiState.email = appleId
        sut.emailDidChange()
        sut.useDifferentPassword()

        XCTAssertFalse(sut.uiState.usesSavedPassword)
        XCTAssertFalse(sut.uiState.savesPassword, "the toggle shows the off again")
    }

    func testSignInAgainPromptWithTheSavedPasswordRefreshesIt() async {
        keychain.set("saved", forKey: passwordKey)
        flow.startResults = [.success(needsCode())]
        flow.submitResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT(.signInAgain(appleId: appleId))
        await sut.signInWithSavedPasswordIfAvailable()
        XCTAssertTrue(sut.uiState.usesSavedPassword)
        XCTAssertTrue(sut.uiState.savesPassword, "the toggle is never shown here, so it stays on")

        await sut.updateCode("123456")

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved")
        XCTAssertEqual(keychain.writtenKeys.filter { $0 == passwordKey }.count, 2, "written again once signed in: refreshed, not just left")
    }

    func testSavePasswordToggleIsTrackedWithoutThePassword() {
        let sut = makeSUT()

        sut.setSavesPassword(false)
        sut.setSavesPassword(true)
        sut.setSavesPassword(true)
        sut.setSavesPassword(false)

        XCTAssertEqual(taps(.savePasswordOn).count, 1, "only a change is tracked")
        XCTAssertEqual(taps(.savePasswordOff).count, 1)
        XCTAssertFalse(sut.uiState.savesPassword)
        for event in taps(.savePasswordOff) + taps(.savePasswordOn) {
            XCTAssertEqual(Set(event.parameters.keys), [AnalyticsParameterKey.buttonName, AnalyticsParameterKey.screenName])
        }
    }

    // MARK: - Cancel

    func testClosingBeforeTheEndIsTrackedAsCancelled() async {
        flow.startResults = [.success(needsCode())]
        let sut = makeSUT()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"
        await sut.signIn()

        sut.discard()
        sut.discard()

        let cancelled = actions(.appleIdSignIn).filter { $0.parameters[AnalyticsParameterKey.result] == .string("cancelled") }
        XCTAssertEqual(cancelled.count, 1)
    }

    func testClosingAfterSavingIsNotACancel() async {
        let sut = await signedInSUT(teams: [.fixture(1, "Alpha")])
        await sut.save()

        sut.discard()

        XCTAssertFalse(actions(.appleIdSignIn).contains { $0.parameters[AnalyticsParameterKey.result] == .string("cancelled") })
    }
}
