import LinkPresentation
import UIKit
import XCTest
@testable import StackConnect

/// Covers Home's "ask the Account Holder" share action on the pending-agreements
/// banner: Account Holder lookup, the generic fallbacks, the per-account loading
/// flag and the activity items handed to the share sheet.
@MainActor
final class HomeViewModelAgreementShareTests: XCTestCase {

    private var storage: MockPersistentStorable!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
    }

    override func tearDown() async throws {
        storage = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private let teamName = "Acme Team"

    private func makeFlaggedAccount() -> AccountModel {
        AccountModel(
            id: "acc-1",
            name: teamName,
            providerType: .apple,
            hasPendingAgreements: true,
            pendingAgreementsDetectedAt: .now
        )
    }

    private func makeUser(
        id: String,
        firstName: String?,
        lastName: String?,
        email: String?,
        roles: [String]
    ) -> UserModel {
        UserModel(
            id: id,
            firstName: firstName,
            lastName: lastName,
            email: email,
            roles: roles,
            allAppsVisible: true,
            provisioningAllowed: false,
            isPending: false,
            expirationDate: nil
        )
    }

    private var accountHolder: UserModel {
        makeUser(
            id: "holder",
            firstName: "Jane",
            lastName: "Appleseed",
            email: "jane@example.com",
            roles: [UserRoleCatalog.accountHolder, "ADMIN"]
        )
    }

    private var developer: UserModel {
        makeUser(
            id: "dev",
            firstName: "Dev",
            lastName: "Eloper",
            email: "dev@example.com",
            roles: ["DEVELOPER"]
        )
    }

    /// Builds the SUT with an injected team-members source (never the network)
    /// and loads the dashboard so `account` shows up as a pending-agreements banner.
    private func makeSUT(
        account: AccountModel,
        fetcher: (any TeamUsersFetching)?
    ) async throws -> HomeViewModel {
        try await storage.save(account, id: account.id)
        let sut = HomeViewModel(
            storage: storage,
            keychain: MockKeyStorable(),
            preferences: MockKeyStorable(),
            syncService: .shared,
            teamUsersFetcherFactory: { _ in fetcher }
        )
        await sut.loadDashboard()
        XCTAssertEqual(sut.uiState.pendingAgreementsAccounts.map(\.id), [account.id])
        return sut
    }

    private var fallbackMessage: AgreementShareMessage {
        AgreementShareMessage.make(teamName: teamName, accountHolder: nil)
    }

    // MARK: - Account Holder found

    func testAccountHolderFoundSharesPersonalizedMessage() async throws {
        let account = makeFlaggedAccount()
        let fetcher = MockTeamUsersFetcher(users: [developer, accountHolder])
        let sut = try await makeSUT(account: account, fetcher: fetcher)

        await sut.prepareAgreementShare(accountId: account.id)

        let payload = try XCTUnwrap(sut.uiState.agreementShare)
        XCTAssertEqual(payload.accountId, account.id)
        XCTAssertEqual(fetcher.callCount, 1)

        let message = payload.message
        XCTAssertTrue(message.text.contains("Jane Appleseed"))
        XCTAssertTrue(message.text.contains(teamName))
        XCTAssertTrue(message.text.contains(AppStoreConnectLinks.agreements.absoluteString))
        XCTAssertFalse(message.text.contains("jane@example.com"), "The recipient's email must not be in the body")
        XCTAssertFalse(message.text.contains("Dev Eloper"))
        XCTAssertNotEqual(message.text, fallbackMessage.text)
        XCTAssertEqual(message.recipientTitle, "Jane Appleseed <jane@example.com>")
        XCTAssertEqual(message.url, AppStoreConnectLinks.agreements)
        XCTAssertTrue(sut.uiState.preparingAgreementShareAccountIds.isEmpty)
    }

    func testAccountHolderFoundShareSheetMetadataShowsRecipientEmail() async throws {
        let account = makeFlaggedAccount()
        let sut = try await makeSUT(account: account, fetcher: MockTeamUsersFetcher(users: [accountHolder]))

        await sut.prepareAgreementShare(accountId: account.id)

        let payload = try XCTUnwrap(sut.uiState.agreementShare)
        let source = try XCTUnwrap(payload.shareActivityItems.first as? StackShareTextItemSource)
        let activityController = UIActivityViewController(activityItems: [source], applicationActivities: nil)

        let metadata = try XCTUnwrap(source.activityViewControllerLinkMetadata(activityController))
        XCTAssertEqual(metadata.title, "Jane Appleseed <jane@example.com>")
        XCTAssertTrue(metadata.title?.contains("jane@example.com") ?? false)
        XCTAssertEqual(source.activityViewController(activityController, subjectForActivityType: .mail), payload.message.subject)
        XCTAssertEqual(source.activityViewController(activityController, itemForActivityType: .message) as? String, payload.message.text)
    }

    // MARK: - Fallbacks

    func testAccountHolderMissingFromListFallsBackToGenericMessage() async throws {
        let account = makeFlaggedAccount()
        let fetcher = MockTeamUsersFetcher(users: [developer])
        let sut = try await makeSUT(account: account, fetcher: fetcher)

        await sut.prepareAgreementShare(accountId: account.id)

        let payload = try XCTUnwrap(sut.uiState.agreementShare, "The share sheet must open even without an Account Holder")
        XCTAssertEqual(payload.message, fallbackMessage)
        XCTAssertFalse(payload.message.text.contains("Dev Eloper"))
        XCTAssertTrue(payload.message.text.contains(teamName))
        XCTAssertTrue(payload.message.text.contains(AppStoreConnectLinks.agreements.absoluteString))
        XCTAssertEqual(fetcher.callCount, 1)
        XCTAssertTrue(sut.uiState.preparingAgreementShareAccountIds.isEmpty)
    }

    func testFetchFailureFallsBackToGenericMessage() async throws {
        // e.g. 403 PLA_NOT_ACCEPTED on /v1/users while agreements are pending, or
        // an API key that isn't allowed to list users.
        let account = makeFlaggedAccount()
        let fetcher = MockTeamUsersFetcher(error: MockTeamUsersFetcher.StubError())
        let sut = try await makeSUT(account: account, fetcher: fetcher)

        await sut.prepareAgreementShare(accountId: account.id)

        let payload = try XCTUnwrap(sut.uiState.agreementShare, "A failed lookup must still open the share sheet")
        XCTAssertEqual(payload.accountId, account.id)
        XCTAssertEqual(payload.message, fallbackMessage)
        XCTAssertEqual(fetcher.callCount, 1)
        XCTAssertTrue(sut.uiState.preparingAgreementShareAccountIds.isEmpty)
    }

    func testMissingCredentialsFallsBackWithoutFetching() async throws {
        let account = makeFlaggedAccount()
        let sut = try await makeSUT(account: account, fetcher: nil)

        await sut.prepareAgreementShare(accountId: account.id)

        XCTAssertEqual(sut.uiState.agreementShare?.message, fallbackMessage)
        XCTAssertTrue(sut.uiState.preparingAgreementShareAccountIds.isEmpty)
    }

    func testDefaultLookupWithoutKeychainCredentialsFallsBack() async throws {
        // Exercises the real default factory: no credentials stored → no connection
        // is built (so no network) → generic message.
        let account = makeFlaggedAccount()
        try await storage.save(account, id: account.id)
        let sut = HomeViewModel(
            storage: storage,
            keychain: MockKeyStorable(),
            preferences: MockKeyStorable(),
            syncService: .shared
        )
        await sut.loadDashboard()

        await sut.prepareAgreementShare(accountId: account.id)

        XCTAssertEqual(sut.uiState.agreementShare?.message, fallbackMessage)
    }

    func testFallbackShareSheetMetadataUsesGenericTitle() async throws {
        let account = makeFlaggedAccount()
        let sut = try await makeSUT(account: account, fetcher: MockTeamUsersFetcher(users: []))

        await sut.prepareAgreementShare(accountId: account.id)

        let payload = try XCTUnwrap(sut.uiState.agreementShare)
        let source = try XCTUnwrap(payload.shareActivityItems.first as? StackShareTextItemSource)
        let activityController = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        let metadata = try XCTUnwrap(source.activityViewControllerLinkMetadata(activityController))
        XCTAssertEqual(metadata.title, fallbackMessage.recipientTitle)
        XCTAssertTrue(metadata.title?.contains(teamName) ?? false)
    }

    // MARK: - Loading state

    func testLoadingFlagIsSetWhileFetchingAndClearedAfterwards() async throws {
        let account = makeFlaggedAccount()
        let fetcher = MockTeamUsersFetcher()
        let sut = try await makeSUT(account: account, fetcher: fetcher)
        let observed = LockedValue<Bool?>(nil)
        let accountId = account.id
        let holder = accountHolder
        fetcher.handler = { [sut] in
            let isPreparing = await MainActor.run {
                sut.uiState.preparingAgreementShareAccountIds.contains(accountId)
            }
            observed.value = isPreparing
            return [holder]
        }

        XCTAssertFalse(sut.uiState.preparingAgreementShareAccountIds.contains(accountId))
        await sut.prepareAgreementShare(accountId: accountId)

        XCTAssertEqual(observed.value, true, "The button must show its loading state while fetching")
        XCTAssertFalse(sut.uiState.preparingAgreementShareAccountIds.contains(accountId))
        XCTAssertNotNil(sut.uiState.agreementShare)
    }

    func testLoadingFlagIsClearedAfterFailure() async throws {
        let account = makeFlaggedAccount()
        let sut = try await makeSUT(
            account: account,
            fetcher: MockTeamUsersFetcher(error: MockTeamUsersFetcher.StubError())
        )

        await sut.prepareAgreementShare(accountId: account.id)

        XCTAssertTrue(sut.uiState.preparingAgreementShareAccountIds.isEmpty)
    }

    func testRepeatedTapWhileFetchingIsIgnored() async throws {
        let account = makeFlaggedAccount()
        let fetcher = MockTeamUsersFetcher()
        let sut = try await makeSUT(account: account, fetcher: fetcher)
        let accountId = account.id
        let holder = accountHolder
        fetcher.handler = { [sut] in
            // Simulates a second tap while the first lookup is still in flight.
            await sut.prepareAgreementShare(accountId: accountId)
            return [holder]
        }

        await sut.prepareAgreementShare(accountId: accountId)

        XCTAssertEqual(fetcher.callCount, 1)
        XCTAssertNotNil(sut.uiState.agreementShare)
        XCTAssertTrue(sut.uiState.preparingAgreementShareAccountIds.isEmpty)
    }

    // MARK: - Misc

    func testEachTapFetchesAgainAndProducesANewPayload() async throws {
        // No caching: the Account Holder is looked up on every tap, and every tap
        // yields a distinct payload so the share sheet re-presents.
        let account = makeFlaggedAccount()
        let fetcher = MockTeamUsersFetcher(users: [accountHolder])
        let sut = try await makeSUT(account: account, fetcher: fetcher)

        await sut.prepareAgreementShare(accountId: account.id)
        let first = try XCTUnwrap(sut.uiState.agreementShare)
        sut.uiState.agreementShare = nil // share sheet dismissed
        await sut.prepareAgreementShare(accountId: account.id)
        let second = try XCTUnwrap(sut.uiState.agreementShare)

        XCTAssertEqual(fetcher.callCount, 2)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.message, second.message)
    }

    func testUnknownAccountIsIgnored() async throws {
        let account = makeFlaggedAccount()
        let fetcher = MockTeamUsersFetcher(users: [accountHolder])
        let sut = try await makeSUT(account: account, fetcher: fetcher)

        await sut.prepareAgreementShare(accountId: "not-a-banner-account")

        XCTAssertNil(sut.uiState.agreementShare)
        XCTAssertEqual(fetcher.callCount, 0)
    }
}

// MARK: - Helpers

/// Thread-safe box for values written from a non-isolated mock and read by the test.
private final class LockedValue<Value>: @unchecked Sendable {

    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
