import XCTest
@testable import StackConnect

@MainActor
final class AnalyticsUserPropertiesUpdaterTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var analytics: MockAnalyticsTracker!
    private var center: NotificationCenter!
    private var sut: AnalyticsUserPropertiesUpdater!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        analytics = MockAnalyticsTracker()
        // A private center: the app-wide `.default` is never observed in tests.
        center = NotificationCenter()
        sut = AnalyticsUserPropertiesUpdater(storage: storage, analytics: analytics, notificationCenter: center)
    }

    override func tearDown() async throws {
        sut = nil
        center = nil
        analytics = nil
        storage = nil
        try await super.tearDown()
    }

    private func save(_ provider: ProviderType, name: String = "Account") async throws {
        let account = AccountModel(name: name, providerType: provider)
        try await storage.save(account, id: account.id)
    }

    // MARK: - Mapping

    func testNoAccounts() {
        XCTAssertEqual(AnalyticsUserPropertiesUpdater.properties(for: []), [
            .accountCount: "0",
            .hasApple: "false",
            .hasFirebase: "false",
            .hasGooglePlay: "false"
        ])
    }

    func testProviderFlagsAndCount() {
        let accounts = [
            AccountModel(name: "A", providerType: .apple),
            AccountModel(name: "B", providerType: .googlePlay)
        ]

        XCTAssertEqual(AnalyticsUserPropertiesUpdater.properties(for: accounts), [
            .accountCount: "2",
            .hasApple: "true",
            .hasFirebase: "false",
            .hasGooglePlay: "true"
        ])
    }

    func testAccountCountBuckets() {
        XCTAssertEqual([0, 1, 2, 3, 4, 50].map(AnalyticsUserPropertiesUpdater.accountCountBucket), ["0", "1", "2", "3+", "3+", "3+"])
    }

    func testEveryPropertyIsAlwaysSetAndNoValueCarriesUserData() {
        let accounts = [AccountModel(name: "Secret Team Name", providerType: .firebase)]
        let properties = AnalyticsUserPropertiesUpdater.properties(for: accounts)

        XCTAssertEqual(Set(properties.keys), Set(AnalyticsUserProperty.accountDerived))
        XCTAssertTrue(properties.values.allSatisfy { ["0", "1", "2", "3+", "true", "false"].contains($0) })
    }

    // MARK: - Refresh

    func testRefreshReadsStorage() async throws {
        try await save(.apple)
        try await save(.apple, name: "Other")
        try await save(.firebase)

        await sut.refresh()

        XCTAssertEqual(analytics.userPropertyUpdates.last?[.accountCount], "3+")
        XCTAssertEqual(analytics.userPropertyUpdates.last?[.hasFirebase], "true")
        XCTAssertEqual(analytics.userPropertyUpdates.last?[.hasGooglePlay], "false")
    }

    func testUnreadableAccountsSetNothing() async {
        await storage.failFetchAll(AccountModel.self)

        await sut.refresh()

        XCTAssertTrue(analytics.userPropertyUpdates.isEmpty)
    }

    func testDisabledAnalyticsReceivesNothing() async throws {
        analytics.setEnabled(false)
        try await save(.apple)

        await sut.refresh()

        XCTAssertTrue(analytics.userPropertyUpdates.isEmpty)
    }

    // MARK: - Triggers

    func testStartComputesOnce() async {
        sut.start()
        await sut.pendingRefresh?.value

        XCTAssertEqual(analytics.userPropertyUpdates.count, 1)
        XCTAssertEqual(analytics.userPropertyUpdates.first?[.accountCount], "0")
    }

    func testAccountsChangeRecomputes() async throws {
        sut.start()
        await sut.pendingRefresh?.value
        try await save(.googlePlay)

        AccountsChange.post(center: center)
        // The observer hops to the main actor before scheduling the refresh.
        for _ in 0..<50 where analytics.userPropertyUpdates.count < 2 {
            await Task.yield()
            await sut.pendingRefresh?.value
        }

        XCTAssertEqual(analytics.userPropertyUpdates.count, 2)
        XCTAssertEqual(analytics.userPropertyUpdates.last?[.hasGooglePlay], "true")
        XCTAssertEqual(analytics.userPropertyUpdates.last?[.accountCount], "1")
    }

    func testCascadeDeletePostsAccountsChange() async throws {
        let account = AccountModel(name: "Gone", providerType: .apple)
        try await storage.save(account, id: account.id)
        let posted = expectation(forNotification: .accountsDidChange, object: nil)

        try await AccountCascadeDeleter.delete(account, storage: storage, keychain: MockKeyStorable())

        await fulfillment(of: [posted], timeout: 1)
    }
}
