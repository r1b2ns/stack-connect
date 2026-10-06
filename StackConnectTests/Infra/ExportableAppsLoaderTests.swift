import XCTest
@testable import StackConnect

final class ExportableAppsLoaderTests: XCTestCase {

    private var storage: MockPersistentStorable!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
    }

    override func tearDown() async throws {
        storage = nil
        try await super.tearDown()
    }

    func testAppleAppsComeFromTheAccountsAppModelsSortedByName() async throws {
        let account = AccountModel(name: "Team", providerType: .apple)
        let apps = [
            AppModel(id: "2", name: "Zeta", bundleId: "com.zeta", accountId: account.id, iconUrl: "https://example.com/z.png"),
            AppModel(id: "1", name: "Alpha", bundleId: "com.alpha", accountId: account.id),
            AppModel(id: "3", name: "Other", bundleId: "com.other", accountId: "another-account")
        ]
        for app in apps { try await storage.save(app, id: app.id) }

        let exportable = await ExportableAppsLoader.apps(for: account, storage: storage)

        XCTAssertEqual(exportable.map(\.bundleId), ["com.alpha", "com.zeta"])
        XCTAssertEqual(exportable.last?.iconURL, URL(string: "https://example.com/z.png"))
    }

    func testGooglePlayAppsComeFromTheCachedListWithPackageNamesAsScopeKeys() async throws {
        let account = AccountModel(name: "Play", providerType: .googlePlay)
        let cached = [
            GooglePlayAppItem(id: "com.b", packageName: "com.b", title: "bravo", isManuallyAdded: false),
            GooglePlayAppItem(id: "com.a", packageName: "com.a", title: nil, isManuallyAdded: true),
            GooglePlayAppItem(id: "com.c", packageName: "com.c", title: "Alpha", isManuallyAdded: false)
        ]
        try await storage.save(cached, id: GooglePlayAppItem.cacheKey(accountId: account.id))
        // App Store apps of the same account id are not Play apps.
        try await storage.save(AppModel(id: "x", name: "iOS", bundleId: "com.ios", accountId: account.id), id: "x")

        let exportable = await ExportableAppsLoader.apps(for: account, storage: storage)

        XCTAssertEqual(exportable.map(\.name), ["Alpha", "bravo", "com.a"], "Display name, case-insensitive order")
        XCTAssertEqual(exportable.map(\.bundleId), ["com.c", "com.b", "com.a"])
        XCTAssertTrue(exportable.allSatisfy { $0.iconURL == nil })
    }

    func testGooglePlayWithoutACachedListHasNoApps() async {
        let account = AccountModel(name: "Play", providerType: .googlePlay)

        let exportable = await ExportableAppsLoader.apps(for: account, storage: storage)

        XCTAssertTrue(exportable.isEmpty)
    }

    func testFirebaseHasNoApps() async throws {
        let account = AccountModel(name: "Firebase", providerType: .firebase)
        try await storage.save(AppModel(id: "1", name: "A", bundleId: "com.a", accountId: account.id), id: "1")

        let exportable = await ExportableAppsLoader.apps(for: account, storage: storage)

        XCTAssertTrue(exportable.isEmpty)
    }
}
