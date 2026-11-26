import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// Reconnecting an Apple ID account whose session reference
/// (`credentials.{id}`) is gone (`.reconnectAccount`): the Apple ID is typed
/// (prefilled only when unambiguous), the saved password applies as usual,
/// and signing in restores the account's reference instead of adding one.
@MainActor
final class AppleIdSignInReconnectAccountTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private var status: MockAppleSessionStatus!
    private var flow: MockAppleIdSignIn!
    private var account: AccountModel!

    private let appleId = "dev@example.com"
    private var passwordKey: String { "applePassword.\(appleId)" }

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        status = MockAppleSessionStatus()
        flow = MockAppleIdSignIn()
        let account = AccountModel(name: "Acme", providerType: .apple, authMethod: .appleIdSignIn)
        // Saved as `AccountModel`, not through the implicitly unwrapped
        // property (which would store it as `Optional<AccountModel>`).
        try await storage.save(account, id: account.id)
        self.account = account
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        analytics = nil
        status = nil
        flow = nil
        account = nil
        try await super.tearDown()
    }

    private func makeSUT() -> AppleIdSignInViewModel {
        AppleIdSignInViewModel(
            mode: .reconnectAccount(accountId: account.id, accountName: account.name),
            storage: storage,
            keychain: keychain,
            sessionStatus: status,
            roleResolver: MockAppleSessionRoleResolver(),
            analytics: analytics,
            makeSignIn: { [unowned self] _ in self.flow }
        )
    }

    /// Another account of `appleId` with a working reference, on `teamId`.
    @discardableResult
    private func addOtherAccount(appleId: String, teamId: UInt64, name: String) async throws -> AccountModel {
        let other = AccountModel(name: name, providerType: .apple, authMethod: .appleIdSignIn)
        keychain.setObject(AppleCredentials(webSession: AppleWebSessionReference(appleId: appleId, teamId: teamId, teamName: name)),
                           forKey: "credentials.\(other.id)")
        try await storage.save(other, id: other.id)
        return other
    }

    private var restoredReference: AppleWebSessionReference? {
        AppleSessionReferences.reference(of: account, keychain: keychain)
    }

    // MARK: - The Apple ID

    func testStartsWithAnEditableEmptyAppleIdAndThePasswordField() async {
        let sut = makeSUT()

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertEqual(sut.uiState.email, "")
        XCTAssertTrue(sut.uiState.isEmailEditable)
        XCTAssertFalse(sut.uiState.usesSavedPassword)
        XCTAssertTrue(sut.uiState.mode.renewsSession)
        XCTAssertTrue(flow.starts.isEmpty)
    }

    func testTheOnlyAppleIdInUseIsPrefilledAndItsSavedPasswordOffered() async throws {
        try await addOtherAccount(appleId: appleId, teamId: 9, name: "Other Team")
        keychain.set("saved", forKey: passwordKey)
        let sut = makeSUT()

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertEqual(sut.uiState.email, appleId, "the fallback resolves")
        XCTAssertTrue(sut.uiState.isEmailEditable, "a suggestion only: still editable")
        XCTAssertTrue(sut.uiState.usesSavedPassword, "no typing")
        XCTAssertTrue(sut.uiState.canSignIn)
        XCTAssertTrue(flow.starts.isEmpty, "not sent before a tap (the Apple ID is a guess)")
    }

    func testAnExpiredAppleIdIsAFallbackToo() async {
        status.markExpired(appleId: appleId)
        let sut = makeSUT()

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertEqual(sut.uiState.email, appleId)
    }

    func testSeveralAppleIdsAreNeverGuessed() async throws {
        try await addOtherAccount(appleId: appleId, teamId: 9, name: "Other Team")
        try await addOtherAccount(appleId: "second@example.com", teamId: 3, name: "Third")
        let sut = makeSUT()

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertEqual(sut.uiState.email, "")
    }

    func testATypedAppleIdWithASavedPasswordUsesIt() async {
        keychain.set("saved", forKey: passwordKey)
        flow.startResults = [.success(.done(teams: [.fixture(1, "Acme")]))]
        let sut = makeSUT()
        await sut.signInWithSavedPasswordIfAvailable()

        sut.uiState.email = appleId
        sut.emailDidChange()
        XCTAssertTrue(sut.uiState.usesSavedPassword)
        await sut.signIn()

        XCTAssertEqual(flow.starts, [.init(email: appleId, password: "saved")])
        XCTAssertEqual(sut.uiState.step, .finished)
    }

    // MARK: - Restoring the reference

    func testSigningInRestoresTheReferenceAndRenewsTheSession() async throws {
        let other = try await addOtherAccount(appleId: appleId, teamId: 9, name: "Other Team")
        status.markExpired(appleId: appleId)
        flow.startResults = [.success(needsCode)]
        flow.submitResults = [.success(.done(teams: [.fixture(9, "Other Team"), .fixture(1, "Acme")]))]
        flow.finishResult = .success(Data("new-session".utf8))
        let sut = makeSUT()
        await sut.signInWithSavedPasswordIfAvailable()
        sut.uiState.password = "secret"

        await sut.signIn()
        await sut.updateCode("123456")

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertEqual(restoredReference, AppleWebSessionReference(appleId: appleId, teamId: 1, teamName: "Acme"))
        XCTAssertEqual(AppleSessionReferences.reference(of: other, keychain: keychain)?.teamId, 9, "the other account is untouched")
        XCTAssertEqual(keychain.data(forKey: "appleSession.\(appleId)"), Data("new-session".utf8), "one session renewed for every team account")
        XCTAssertEqual(status.markedValid, [appleId])
        let accounts = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(Set(accounts.map(\.id)), [account.id, other.id], "no account added")
    }

    func testAnAmbiguousTeamRenewsTheSessionButExplains() async throws {
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha"), .fixture(2, "Beta")]))]
        let sut = makeSUT()
        await sut.signInWithSavedPasswordIfAvailable()
        sut.uiState.email = appleId
        sut.uiState.password = "secret"

        await sut.signIn()

        XCTAssertNil(restoredReference)
        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.uiState.errorMessage, String(localized: "Signed in, but this account's team wasn't found among the Apple ID's teams. Remove the account and add it again."))
        XCTAssertNotNil(keychain.data(forKey: "appleSession.\(appleId)"), "the Apple ID's other accounts work again")
    }

    // MARK: - Matching the team

    func testMatchingTeamOnlyWhenThereIsNoDoubt() {
        let acme = AppleTeam.fixture(1, "Acme")
        let other = AppleTeam.fixture(2, "Other")
        let acmeTwin = AppleTeam.fixture(3, "acme ")

        XCTAssertEqual(AppleIdSignInViewModel.matchingTeam(forAccountNamed: "Acme", in: [other, acme], takenTeamIds: [])?.providerId, 1, "by name")
        XCTAssertEqual(AppleIdSignInViewModel.matchingTeam(forAccountNamed: "Renamed", in: [acme, other], takenTeamIds: [1])?.providerId, 2,
                       "the one team no other account uses")
        XCTAssertEqual(AppleIdSignInViewModel.matchingTeam(forAccountNamed: "Acme", in: [acme, acmeTwin], takenTeamIds: [1])?.providerId, 3,
                       "two teams of that name: the one no other account uses")
        XCTAssertNil(AppleIdSignInViewModel.matchingTeam(forAccountNamed: "Acme", in: [acme, acmeTwin], takenTeamIds: []))
        XCTAssertNil(AppleIdSignInViewModel.matchingTeam(forAccountNamed: "Renamed", in: [acme, other], takenTeamIds: []))
        XCTAssertEqual(AppleIdSignInViewModel.matchingTeam(forAccountNamed: "Renamed", in: [acme], takenTeamIds: [])?.providerId, 1, "the only team")
        XCTAssertNil(AppleIdSignInViewModel.matchingTeam(forAccountNamed: "Acme", in: [], takenTeamIds: []))
    }

    private var needsCode: AppleSignInStep {
        .needsCode(methods: [.trustedDevice], phones: [.fixture], codeLength: 6, delivery: .trustedDevices)
    }
}
