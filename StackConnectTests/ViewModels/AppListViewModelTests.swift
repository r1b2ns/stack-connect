import XCTest
@testable import StackConnect

@MainActor
final class AppListViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        try await super.tearDown()
    }

    private func seedApp(_ id: String, bundleId: String, accountId: String) async throws {
        let app = AppModel(id: id, name: id.uppercased(), bundleId: bundleId, accountId: accountId)
        try await storage.save(app, id: "\(accountId).\(id)")
    }

    /// Read-side defense-in-depth: cached apps outside the per-app scope must be
    /// filtered out of the visible list. No credentials are set, so `loadApps`
    /// returns right after the offline-first cache read.
    func testLoadAppsFiltersCachedAppsByScope() async throws {
        let account = AccountModel(
            name: "Scoped",
            providerType: .apple,
            origin: .imported,
            appsBundles: ["com.a", "com.c"]
        )
        try await seedApp("a", bundleId: "com.a", accountId: account.id)
        try await seedApp("b", bundleId: "com.b", accountId: account.id)
        try await seedApp("c", bundleId: "com.c", accountId: account.id)

        let sut = AppListViewModel(account: account, storage: storage, keychain: keychain)
        await sut.loadApps()

        let bundles = Set(sut.uiState.apps.map(\.bundleId))
        XCTAssertEqual(bundles, ["com.a", "com.c"])
        XCTAssertFalse(bundles.contains("com.b"))
    }

    /// nil scope ⇒ all cached apps remain visible.
    func testLoadAppsWithUnrestrictedScopeKeepsAllCachedApps() async throws {
        let account = AccountModel(name: "Free", providerType: .apple, appsBundles: nil)
        try await seedApp("a", bundleId: "com.a", accountId: account.id)
        try await seedApp("b", bundleId: "com.b", accountId: account.id)

        let sut = AppListViewModel(account: account, storage: storage, keychain: keychain)
        await sut.loadApps()

        XCTAssertEqual(Set(sut.uiState.apps.map(\.bundleId)), ["com.a", "com.b"])
    }
}
