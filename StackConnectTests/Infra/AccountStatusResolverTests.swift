import Combine
import XCTest
@testable import StackConnect

/// Which accounts show "Disconnected" / "Action Needed", from local data only.
@MainActor
final class AccountStatusResolverTests: XCTestCase {

    private var keychain: MockKeyStorable!
    private var appleStatus: MockAppleSessionStatus!
    private var googleStatus: MockGoogleLoginStatus!
    private let appleId = "dev@example.com"

    override func setUp() async throws {
        try await super.setUp()
        keychain = MockKeyStorable()
        appleStatus = MockAppleSessionStatus()
        googleStatus = MockGoogleLoginStatus()
    }

    override func tearDown() async throws {
        keychain = nil
        appleStatus = nil
        googleStatus = nil
        try await super.tearDown()
    }

    private func makeSUT() -> AccountStatusResolver {
        AccountStatusResolver(
            keychain: keychain,
            signInExpiry: ExpiredSignInResolver(keychain: keychain, appleStatus: appleStatus, googleStatus: googleStatus)
        )
    }

    // MARK: - Fixtures

    private func apiKeyAccount(_ name: String = "Key", hasPendingAgreements: Bool = false) -> AccountModel {
        let account = AccountModel(name: name, providerType: .apple, hasPendingAgreements: hasPendingAgreements)
        keychain.setObject(AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "key"), forKey: "credentials.\(account.id)")
        return account
    }

    private func appleIdAccount() -> AccountModel {
        let account = AccountModel(name: "Session", providerType: .apple, authMethod: .appleIdSignIn)
        keychain.setObject(
            AppleCredentials(webSession: .init(appleId: appleId, teamId: 1, teamName: "Team")),
            forKey: "credentials.\(account.id)"
        )
        return account
    }

    private func googleAccount(provider: ProviderType = .googlePlay, storeGrant: Bool = true) -> AccountModel {
        let account = AccountModel(name: "Google", providerType: provider, authMethod: .googleSignIn)
        if provider == .firebase {
            keychain.setObject(FirebaseCredentials(googleLoginId: "user-1"), forKey: "credentials.\(account.id)")
        } else {
            keychain.setObject(GooglePlayCredentials(googleLoginId: "user-1"), forKey: "credentials.\(account.id)")
        }
        if storeGrant {
            GoogleLoginKeychainStore(keychain: keychain).save(GoogleAuthFixtures.grant(loginId: "user-1"))
        }
        return account
    }

    // MARK: - No issue

    func testWorkingAccountsHaveNoStatus() {
        let accounts = [apiKeyAccount(), appleIdAccount(), googleAccount()]

        XCTAssertTrue(makeSUT().statuses(for: accounts).isEmpty)
    }

    // MARK: - Disconnected

    func testExpiredAppleIdSessionIsDisconnected() {
        let account = appleIdAccount()
        appleStatus.markExpired(appleId: appleId)

        let status = makeSUT().status(for: account)

        XCTAssertEqual(status?.level, .disconnected)
        XCTAssertEqual(status?.issues, [.signInExpired])
    }

    func testExpiredGoogleLoginIsDisconnected() {
        let account = googleAccount(provider: .firebase)
        googleStatus.markExpired(loginId: "user-1")

        XCTAssertEqual(makeSUT().status(for: account)?.issues, [.signInExpired])
    }

    func testMissingGoogleGrantIsDisconnected() {
        let account = googleAccount(storeGrant: false)

        XCTAssertEqual(makeSUT().status(for: account)?.issues, [.signInExpired])
    }

    func testExpiredImportedFileIsDisconnected() {
        var account = apiKeyAccount()
        account.origin = .imported
        account.expirationDate = Date().addingTimeInterval(-60)

        let status = makeSUT().status(for: account)

        XCTAssertEqual(status?.level, .disconnected)
        XCTAssertEqual(status?.issues, [.accessExpired])
    }

    func testMissingCredentialsIsDisconnected() {
        let account = AccountModel(name: "No keys", providerType: .firebase)

        XCTAssertEqual(makeSUT().status(for: account)?.issues, [.missingCredentials])
    }

    // MARK: - Needs attention

    func testPendingAgreementsNeedAttention() {
        let account = apiKeyAccount(hasPendingAgreements: true)

        let status = makeSUT().status(for: account)

        XCTAssertEqual(status?.level, .needsAttention)
        XCTAssertEqual(status?.issues, [.pendingAgreements])
    }

    func testPendingAgreementsFlagIsIgnoredOutsideAppStoreConnect() {
        var account = googleAccount()
        account.hasPendingAgreements = true

        XCTAssertNil(makeSUT().status(for: account))
    }

    func testFileExpiringSoonNeedsAttention() {
        var account = apiKeyAccount()
        account.origin = .imported
        account.expirationDate = Date().addingTimeInterval(60 * 60)

        XCTAssertEqual(makeSUT().status(for: account)?.issues, [.accessExpiringSoon])
    }

    func testFileExpiringLaterHasNoStatus() {
        var account = apiKeyAccount()
        account.origin = .imported
        account.expirationDate = Date().addingTimeInterval(3 * 24 * 60 * 60)

        XCTAssertNil(makeSUT().status(for: account))
    }

    // MARK: - Several issues

    func testDisconnectedWinsOverNeedsAttentionAndLeadsTheIssues() {
        var account = AccountModel(name: "Both", providerType: .apple, hasPendingAgreements: true)
        account.expirationDate = Date().addingTimeInterval(-60)

        let status = makeSUT().status(for: account)

        XCTAssertEqual(status?.level, .disconnected)
        XCTAssertEqual(status?.issues, [.accessExpired, .missingCredentials, .pendingAgreements])
    }

    func testStatusesAreKeyedByAccountAndSkipHealthyOnes() {
        let healthy = apiKeyAccount("Healthy")
        let pending = apiKeyAccount("Pending", hasPendingAgreements: true)
        let session = appleIdAccount()
        appleStatus.markExpired(appleId: appleId)

        let statuses = makeSUT().statuses(for: [healthy, pending, session])

        XCTAssertEqual(Set(statuses.keys), [pending.id, session.id])
        XCTAssertEqual(statuses[pending.id]?.level, .needsAttention)
        XCTAssertEqual(statuses[session.id]?.level, .disconnected)
    }

    func testModelRejectsAnEmptyIssueList() {
        XCTAssertNil(AccountStatus(issues: []))
        XCTAssertEqual(AccountStatus(issues: [.pendingAgreements, .pendingAgreements])?.issues, [.pendingAgreements])
    }

    // MARK: - Service

    func testServiceReadsTheFreshestStoredAccount() async throws {
        let storage = MockPersistentStorable()
        var account = apiKeyAccount()
        try await storage.save(account, id: account.id)
        let sut = AccountStatusService(
            storage: storage,
            keychain: keychain,
            resolver: makeSUT(),
            notificationCenter: NotificationCenter(),
            syncFinished: Empty<Void, Never>().eraseToAnyPublisher()
        )

        let before = await sut.status(forAccountId: account.id)
        XCTAssertNil(before)

        account.hasPendingAgreements = true
        try await storage.save(account, id: account.id)
        let after = await sut.status(forAccountId: account.id)
        XCTAssertEqual(after?.issues, [.pendingAgreements])

        let unknown = await sut.status(forAccountId: "missing")
        XCTAssertNil(unknown)
    }

    func testServiceSignalsSignInAndSyncChanges() async {
        let center = NotificationCenter()
        let sync = PassthroughSubject<Void, Never>()
        let sut = AccountStatusService(
            storage: MockPersistentStorable(),
            keychain: keychain,
            resolver: makeSUT(),
            notificationCenter: center,
            syncFinished: sync.eraseToAnyPublisher()
        )
        let received = expectation(description: "two changes")
        received.expectedFulfillmentCount = 2
        let cancellable = sut.changes.sink { received.fulfill() }

        center.postSignInStatusDidChange()
        sync.send(())

        await fulfillment(of: [received], timeout: 2)
        cancellable.cancel()
    }
}
