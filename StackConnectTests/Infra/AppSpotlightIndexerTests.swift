import Combine
import CoreSpotlight
import XCTest
@testable import StackConnect

/// Records what the indexer would write to Spotlight.
private actor MockSpotlightIndexWriter: AppSpotlightIndexWriting {
    private(set) var writes: [[AppSpotlightEntry]] = []

    func replaceAll(with entries: [AppSpotlightEntry]) async throws {
        writes.append(entries)
    }
}

@MainActor
final class AppSpotlightIndexerTests: XCTestCase {

    private let apple = AccountModel(id: "asc", name: "ASC", providerType: .apple)
    private let play = AccountModel(id: "play", name: "Play", providerType: .googlePlay)
    private let firebase = AccountModel(id: "fb", name: "Firebase", providerType: .firebase)

    // MARK: - Mapping

    func testEntriesOpenEachAppThroughItsDeepLink() throws {
        let pulse = AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: apple.id)
        let trail = GooglePlayAppItem(id: "com.trail", packageName: "com.trail", title: "Trail", isManuallyAdded: false)

        let entries = AppSpotlightIndexer.entries(
            accounts: [apple, play, firebase],
            apps: [pulse],
            googlePlayApps: [play.id: [trail]]
        )

        XCTAssertEqual(entries, [
            AppSpotlightEntry(url: DeepLink.app(accountId: apple.id, appId: "1").url, accountId: apple.id, name: "Pulse", bundleId: "com.pulse"),
            AppSpotlightEntry(url: DeepLink.app(accountId: play.id, appId: "com.trail").url, accountId: play.id, name: "Trail", bundleId: "com.trail")
        ])
    }

    func testEntriesLeaveOutArchivedOtherAccountsAndOutOfScopeApps() {
        let scoped = AccountModel(id: "asc", name: "ASC", providerType: .apple, appsBundles: ["com.pulse", "com.old"])
        let apps = [
            AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: scoped.id),
            AppModel(id: "2", name: "Old", bundleId: "com.old", accountId: scoped.id, isArchived: true),
            AppModel(id: "3", name: "Other", bundleId: "com.other", accountId: scoped.id),
            AppModel(id: "4", name: "Gone", bundleId: "com.gone", accountId: "deleted-account")
        ]

        let entries = AppSpotlightIndexer.entries(accounts: [scoped], apps: apps, googlePlayApps: [:])

        XCTAssertEqual(entries.map(\.name), ["Pulse"])
    }

    // MARK: - Rebuild

    func testRebuildIndexesOnlyTheVisibleStores() async throws {
        let storage = MockPersistentStorable()
        try await storage.save(apple, id: apple.id)
        try await storage.save(play, id: play.id)
        try await storage.save(AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: apple.id), id: "\(apple.id).1")
        try await storage.save([GooglePlayAppItem(id: "com.t", packageName: "com.t", title: "T", isManuallyAdded: false)],
                               id: GooglePlayAppItem.cacheKey(accountId: play.id))
        let writer = MockSpotlightIndexWriter()
        let sut = AppSpotlightIndexer(storage: storage, writer: writer, featureFlags: .googlePlayOff)

        await sut.rebuild()

        let writes = await writer.writes
        XCTAssertEqual(writes.map { $0.map(\.name) }, [["Pulse"]], "Google Play is hidden: never in Spotlight")
    }

    func testADeletedAccountLeavesTheIndexOnTheNextAccountChange() async throws {
        let storage = MockPersistentStorable()
        let center = NotificationCenter()
        try await storage.save(apple, id: apple.id)
        try await storage.save(AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: apple.id), id: "\(apple.id).1")
        let writer = MockSpotlightIndexWriter()
        let sut = AppSpotlightIndexer(storage: storage, writer: writer, featureFlags: .googlePlayOff, notificationCenter: center)
        sut.start(syncState: Empty().eraseToAnyPublisher())
        await sut.pendingRebuild?.value

        // What `AccountCascadeDeleter` does: remove the data, then post.
        try await storage.delete(AppModel.self, id: "\(apple.id).1")
        try await storage.delete(AccountModel.self, id: apple.id)
        AccountsChange.post(center: center)
        try await waitForWrites(writer, count: 2)

        let writes = await writer.writes
        XCTAssertEqual(writes.map(\.count), [1, 0])
    }

    func testAFinishedSyncRebuildsTheIndex() async throws {
        let storage = MockPersistentStorable()
        let writer = MockSpotlightIndexWriter()
        let state = CurrentValueSubject<SyncState, Never>(SyncState())
        let sut = AppSpotlightIndexer(storage: storage, writer: writer, featureFlags: .googlePlayOff, notificationCenter: NotificationCenter())
        sut.start(syncState: state.eraseToAnyPublisher())
        await sut.pendingRebuild?.value

        state.value.isSyncing = true
        try await storage.save(apple, id: apple.id)
        try await storage.save(AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: apple.id), id: "\(apple.id).1")
        state.value.isSyncing = false
        try await waitForWrites(writer, count: 2)

        let writes = await writer.writes
        XCTAssertEqual(writes.map(\.count), [0, 1], "Launch, then the end of the sync — not its start")
    }

    // MARK: - Opening a result

    func testATappedResultOpensItsDeepLink() {
        let url = DeepLink.app(accountId: "asc", appId: "1").url
        XCTAssertEqual(AppSpotlightIndexer.deepLinkURL(from: [CSSearchableItemActivityIdentifier: url.absoluteString]), url)
        XCTAssertNil(AppSpotlightIndexer.deepLinkURL(from: [CSSearchableItemActivityIdentifier: "https://example.com"]))
        XCTAssertNil(AppSpotlightIndexer.deepLinkURL(from: nil))
    }

    // MARK: - Helpers

    private func waitForWrites(_ writer: MockSpotlightIndexWriter, count: Int) async throws {
        for _ in 0..<200 {
            if await writer.writes.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(count) index writes")
    }
}
