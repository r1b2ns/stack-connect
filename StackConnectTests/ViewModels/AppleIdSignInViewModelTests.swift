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
