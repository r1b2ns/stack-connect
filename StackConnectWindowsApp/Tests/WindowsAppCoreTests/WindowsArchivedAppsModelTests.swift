import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Focused unit tests for `WindowsArchivedAppsModel` (T-W07).
/// Covers: TC-009 (load + restore + persistence), TC-058 (archived app
/// appears after restart), AC-W04-5 (empty archived state), restore
/// persists across restart, and revert-on-failure when persistence throws.
@MainActor
final class WindowsArchivedAppsModelTests: XCTestCase {

    private var storage: MockStorage!
    private let accountId = "acc1"

    override func setUp() async throws {
        try await super.setUp()
        storage = MockStorage()
    }

    override func tearDown() async throws {
        storage = nil
        try await super.tearDown()
    }

    /// Helper: creates a SUT with the shared storage.
    private func makeSUT() -> WindowsArchivedAppsModel {
        WindowsArchivedAppsModel(
            accountId: accountId,
            storage: storage
        )
    }

    /// Helper: seeds apps into storage for the test account.
    private func seedApps(_ apps: [AppModel]) async {
        for app in apps {
            try! await storage.save(app, id: "\(accountId).\(app.id)")
        }
    }

    /// Helper: creates a simple AppModel for the test account.
    private func makeApp(
        id: String,
        name: String,
        bundleId: String = "com.example",
        isFavorite: Bool = false,
        isArchived: Bool = false,
        appStoreState: AppStoreState? = nil
    ) -> AppModel {
        AppModel(
            id: id,
            name: name,
            bundleId: bundleId,
            accountId: accountId,
            appStoreState: appStoreState,
            isArchived: isArchived,
            isFavorite: isFavorite
        )
    }

    // MARK: - TC-009: Load 1 archived app -> restore removes it -> isArchived=false persisted

    func testLoadArchivedAppThenRestoreRemovesIt() async {
        // Given: 1 archived app + 1 active app
        let apps = [
            makeApp(id: "a", name: "Active App", bundleId: "com.active"),
            makeApp(id: "b", name: "Archived App", bundleId: "com.archived", isArchived: true),
        ]
        await seedApps(apps)

        let sut = makeSUT()
        await sut.loadArchivedApps()

        // Then: only the archived app is loaded
        XCTAssertEqual(sut.archivedApps.count, 1)
        XCTAssertEqual(sut.archivedApps.first?.id, "b")
        XCTAssertTrue(sut.archivedApps.first!.isArchived)

        // When: restore the archived app (intent + confirm)
        sut.restoreApp(appId: "b")
        XCTAssertEqual(sut.restoreConfirmingId, "b")

        await sut.restoreAppConfirmed(appId: "b")

        // Then: app removed from archived list, confirmation cleared
        XCTAssertTrue(sut.archivedApps.isEmpty)
        XCTAssertNil(sut.restoreConfirmingId)

        // Verify persistence: read back from storage, isArchived should be false
        let persisted: AppModel? = try! await storage.fetch(AppModel.self, id: "\(accountId).b")
        XCTAssertNotNil(persisted)
        XCTAssertFalse(persisted!.isArchived)
    }

    // MARK: - AC-W04-5: Empty archived state when nothing is archived

    func testEmptyArchivedStateWhenNothingArchived() async {
        // Given: only active apps, no archived
        let apps = [
            makeApp(id: "a", name: "Active 1", bundleId: "com.a"),
            makeApp(id: "b", name: "Active 2", bundleId: "com.b"),
        ]
        await seedApps(apps)

        let sut = makeSUT()
        await sut.loadArchivedApps()

        // Then: empty state
        XCTAssertTrue(sut.archivedApps.isEmpty)
        XCTAssertTrue(sut.isEmpty)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - AC-W04-5: Empty archived state when cache is completely empty

    func testEmptyArchivedStateWhenCacheEmpty() async {
        let sut = makeSUT()
        await sut.loadArchivedApps()

        XCTAssertTrue(sut.archivedApps.isEmpty)
        XCTAssertTrue(sut.isEmpty)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - TC-058: Archived app appears in archived screen after archive + restart

    func testArchivedAppAppearsAfterRestart() async {
        // Given: an archived app in storage (simulating archive from apps list)
        let archived = makeApp(id: "a", name: "My App", bundleId: "com.test", isArchived: true)
        await seedApps([archived])

        // First instance loads and sees the archived app
        let sut1 = makeSUT()
        await sut1.loadArchivedApps()
        XCTAssertEqual(sut1.archivedApps.count, 1)
        XCTAssertEqual(sut1.archivedApps.first?.id, "a")
        XCTAssertTrue(sut1.archivedApps.first!.isArchived)

        // "Restart": new model instance, same storage
        let sut2 = makeSUT()
        await sut2.loadArchivedApps()
        XCTAssertEqual(sut2.archivedApps.count, 1)
        XCTAssertEqual(sut2.archivedApps.first?.id, "a")
        XCTAssertTrue(sut2.archivedApps.first!.isArchived)
    }

    // MARK: - Restore persists across restart (new model instance)

    func testRestorePersistsAcrossRestart() async {
        // Given: 1 archived app
        let archived = makeApp(id: "a", name: "My App", bundleId: "com.test", isArchived: true)
        await seedApps([archived])

        // First instance: load and restore
        let sut1 = makeSUT()
        await sut1.loadArchivedApps()
        XCTAssertEqual(sut1.archivedApps.count, 1)

        sut1.restoreApp(appId: "a")
        await sut1.restoreAppConfirmed(appId: "a")
        XCTAssertTrue(sut1.archivedApps.isEmpty)

        // "Restart": new model instance, same storage — restored app should
        // NOT appear in the archived list
        let sut2 = makeSUT()
        await sut2.loadArchivedApps()
        XCTAssertTrue(sut2.archivedApps.isEmpty)
        XCTAssertTrue(sut2.isEmpty)
    }

    // MARK: - Restore revert-on-failure when persistence throws

    func testRestoreRevertsOnPersistenceFailure() async {
        let archived = makeApp(id: "a", name: "My App", bundleId: "com.test", isArchived: true)
        await seedApps([archived])

        let sut = makeSUT()
        await sut.loadArchivedApps()
        XCTAssertEqual(sut.archivedApps.count, 1)

        // Make save fail
        storage.shouldThrowOnSave = true

        sut.restoreApp(appId: "a")
        await sut.restoreAppConfirmed(appId: "a")

        // Reverted: still archived, error set
        XCTAssertEqual(sut.archivedApps.count, 1)
        XCTAssertTrue(sut.archivedApps.first!.isArchived)
        XCTAssertNotNil(sut.syncError)
    }

    // MARK: - Restore cancellation leaves app in archived list

    func testRestoreCancellationLeavesAppInArchivedList() async {
        let archived = makeApp(id: "a", name: "My App", bundleId: "com.test", isArchived: true)
        await seedApps([archived])

        let sut = makeSUT()
        await sut.loadArchivedApps()

        sut.restoreApp(appId: "a")
        XCTAssertEqual(sut.restoreConfirmingId, "a")

        sut.cancelRestore()
        XCTAssertNil(sut.restoreConfirmingId)
        XCTAssertEqual(sut.archivedApps.count, 1)
        XCTAssertTrue(sut.archivedApps.first!.isArchived)
    }

    // MARK: - Only loads archived apps for the configured account

    func testOnlyLoadsArchivedAppsForConfiguredAccount() async {
        // Given: apps from two accounts, only account "acc1" is our target
        let app1 = makeApp(id: "a", name: "My App", bundleId: "com.test", isArchived: true)
        await seedApps([app1])

        // Seed an archived app for a different account
        let otherApp = AppModel(
            id: "x",
            name: "Other App",
            bundleId: "com.other",
            accountId: "acc2",
            isArchived: true
        )
        try! await storage.save(otherApp, id: "acc2.x")

        let sut = makeSUT()
        await sut.loadArchivedApps()

        // Then: only "acc1" archived app loaded
        XCTAssertEqual(sut.archivedApps.count, 1)
        XCTAssertEqual(sut.archivedApps.first?.id, "a")
    }

    // MARK: - Multiple archived apps loaded and sorted

    func testMultipleArchivedAppsLoadedAndSorted() async {
        // Given: 3 archived apps (no dates -> sorted alphabetically by name)
        let apps = [
            makeApp(id: "c", name: "Charlie", bundleId: "com.c", isArchived: true),
            makeApp(id: "a", name: "Alpha", bundleId: "com.a", isArchived: true),
            makeApp(id: "b", name: "Bravo", bundleId: "com.b", isArchived: true),
        ]
        await seedApps(apps)

        let sut = makeSUT()
        await sut.loadArchivedApps()

        XCTAssertEqual(sut.archivedApps.count, 3)
        // Sorted alphabetically: Alpha, Bravo, Charlie
        XCTAssertEqual(sut.archivedApps.map(\.name), ["Alpha", "Bravo", "Charlie"])
        XCTAssertFalse(sut.isEmpty)
    }

    // MARK: - isLoading clears after load completes

    func testIsLoadingClearsAfterLoad() async {
        let sut = makeSUT()

        // Before load
        XCTAssertFalse(sut.isLoading)

        await sut.loadArchivedApps()

        // After load
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Storage fetch failure surfaces syncError (SF#1 coverage)

    func testLoadArchivedAppsHandlesStorageError() async {
        storage.shouldThrowOnFetch = true
        let sut = makeSUT()

        await sut.loadArchivedApps()

        XCTAssertTrue(sut.archivedApps.isEmpty)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNotNil(sut.syncError)
    }

    // MARK: - restoreAppConfirmed for non-existent id clears confirmingId safely

    func testRestoreNonExistentIdClearsConfirmingId() async {
        let archived = makeApp(id: "a", name: "My App", bundleId: "com.test", isArchived: true)
        await seedApps([archived])

        let sut = makeSUT()
        await sut.loadArchivedApps()

        // Attempt to restore an id that does not exist in the archived list
        sut.restoreApp(appId: "nonexistent")
        await sut.restoreAppConfirmed(appId: "nonexistent")

        // Confirming id cleared, archived apps unchanged
        XCTAssertNil(sut.restoreConfirmingId)
        XCTAssertEqual(sut.archivedApps.count, 1)
    }
}
