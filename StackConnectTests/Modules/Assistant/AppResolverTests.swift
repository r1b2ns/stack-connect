import XCTest
@testable import StackConnect

final class AppResolverTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var sut: AppResolver!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        sut = AppResolver(storage: storage)
    }

    override func tearDown() async throws {
        storage = nil
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func seed(_ apps: [AppModel]) async throws {
        for app in apps {
            try await storage.save(app, id: app.id)
        }
    }

    // MARK: - allApps

    func testAllAppsExcludesArchived() async throws {
        try await seed([
            AppModel(id: "1", name: "Alpha", bundleId: "com.a", accountId: "acc"),
            AppModel(id: "2", name: "Beta", bundleId: "com.b", accountId: "acc", isArchived: true)
        ])

        let apps = await sut.allApps()

        XCTAssertEqual(apps.map(\.name), ["Alpha"])
    }

    // MARK: - apps(matching:)

    func testExactNameMatchWinsOverContains() async throws {
        try await seed([
            AppModel(id: "1", name: "Photo", bundleId: "com.photo", accountId: "acc"),
            AppModel(id: "2", name: "Photo Editor", bundleId: "com.photo.editor", accountId: "acc")
        ])

        let matches = await sut.apps(matching: "photo")

        XCTAssertEqual(matches.map(\.id), ["1"])
    }

    func testContainsMatchReturnsMultiple() async throws {
        try await seed([
            AppModel(id: "1", name: "Photo One", bundleId: "com.p1", accountId: "acc"),
            AppModel(id: "2", name: "Photo Two", bundleId: "com.p2", accountId: "acc")
        ])

        let matches = await sut.apps(matching: "Photo")

        XCTAssertEqual(Set(matches.map(\.id)), ["1", "2"])
    }

    func testBundleIdMatch() async throws {
        try await seed([
            AppModel(id: "1", name: "Alpha", bundleId: "com.example.alpha", accountId: "acc")
        ])

        let matches = await sut.apps(matching: "com.example.alpha")

        XCTAssertEqual(matches.map(\.id), ["1"])
    }

    func testBlankQueryReturnsAll() async throws {
        try await seed([
            AppModel(id: "1", name: "Alpha", bundleId: "com.a", accountId: "acc"),
            AppModel(id: "2", name: "Beta", bundleId: "com.b", accountId: "acc")
        ])

        let matches = await sut.apps(matching: "   ")

        XCTAssertEqual(matches.count, 2)
    }

    func testNoMatchReturnsEmpty() async throws {
        try await seed([
            AppModel(id: "1", name: "Alpha", bundleId: "com.a", accountId: "acc")
        ])

        let matches = await sut.apps(matching: "Zeta")

        XCTAssertTrue(matches.isEmpty)
    }

    // MARK: - account(for:)

    func testAccountForAppFillsMissingRules() async throws {
        let account = AccountModel(
            id: "acc",
            name: "Account",
            providerType: .apple,
            rules: AccountRules(),
            origin: .created
        )
        try await storage.save(account, id: account.id)
        let app = AppModel(id: "1", name: "Alpha", bundleId: "com.a", accountId: "acc")

        let resolved = await sut.account(for: app)

        XCTAssertNotNil(resolved)
        // A created account with empty rules has them filled, granting view access.
        XCTAssertTrue(resolved?.canView(.review) ?? false)
    }

    func testAccountForAppReturnsNilWhenMissing() async throws {
        let app = AppModel(id: "1", name: "Alpha", bundleId: "com.a", accountId: "missing")

        let resolved = await sut.account(for: app)

        XCTAssertNil(resolved)
    }
}
