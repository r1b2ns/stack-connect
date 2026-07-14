import Foundation
import XCTest
@testable import StackConnect

/// Home widgets are the only place that reads apps across *every* account
/// (`fetchAll(AppModel.self)`); everywhere else is scoped to the selected
/// account. These tests cover the two ways that flattening used to surface rows
/// nothing else showed: apps duplicated across two registrations of the same ASC
/// team, and apps orphaned by an account that went away.
@MainActor
final class HomeWidgetAccountScopeTests: XCTestCase {

    private var storage: MockPersistentStorable!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
    }

    override func tearDown() async throws {
        storage = nil
        try await super.tearDown()
    }

    // MARK: - Duplicate registration (the reported bug)

    /// The same app reachable through two registered accounts must produce one row
    /// per platform, not one per (account, platform) — and the header count, which
    /// is `apps.count`, must match.
    func testAwaitingReleaseShowsOneRowPerPlatformWhenAppRegisteredUnderTwoAccounts() async throws {
        try await save(account(id: "acc-a"))
        try await save(account(id: "acc-b"))
        let versions = [
            version(.ios, .pendingDeveloperRelease, "3.1.0", id: "v-ios"),
            version(.tvOs, .pendingDeveloperRelease, "3.1.2", id: "v-tv")
        ]
        try await save(multiPlatformApp(id: "app-1", accountId: "acc-a", awaiting: versions))
        try await save(multiPlatformApp(id: "app-1", accountId: "acc-b", awaiting: versions))

        let widget = AwaitingReleaseWidget(configuration: .init(kind: .awaitingRelease), storage: storage)
        await widget.load()

        XCTAssertEqual(widget.apps.count, 2)
        XCTAssertEqual(
            Set(widget.apps.map { AppPlatformVersionKey($0) }),
            [
                AppPlatformVersionKey(platform: AppPlatform.ios.rawValue, version: "3.1.0"),
                AppPlatformVersionKey(platform: AppPlatform.tvOs.rawValue, version: "3.1.2")
            ]
        )
    }

    // MARK: - Orphaned apps

    /// An app whose `accountId` matches no stored account is invisible in Settings
    /// and in the app list; it must be invisible on Home too.
    func testAwaitingReleaseExcludesOrphanedApp() async throws {
        try await save(account(id: "acc-a"))
        try await save(multiPlatformApp(id: "app-live", accountId: "acc-a", awaiting: [version(.ios, .pendingDeveloperRelease, "3.1.0", id: "v-1")]))
        try await save(multiPlatformApp(id: "app-orphan", accountId: "acc-gone", awaiting: [version(.ios, .pendingDeveloperRelease, "9.9.9", id: "v-2")]))

        let widget = AwaitingReleaseWidget(configuration: .init(kind: .awaitingRelease), storage: storage)
        await widget.load()

        XCTAssertEqual(widget.apps.map(\.id), ["app-live"])
    }

    func testInReviewExcludesOrphanedApp() async throws {
        try await save(account(id: "acc-a"))
        try await save(multiPlatformApp(id: "app-live", accountId: "acc-a", platformVersions: [version(.ios, .inReview, "3.1.0", id: "v-1")]))
        try await save(multiPlatformApp(id: "app-orphan", accountId: "acc-gone", platformVersions: [version(.ios, .inReview, "9.9.9", id: "v-2")]))

        let widget = InReviewWidget(configuration: .init(kind: .inReview), storage: storage)
        await widget.load()

        XCTAssertEqual(widget.apps.map(\.id), ["app-live"])
    }

    func testRecentReviewsExcludesReviewsOfOrphanedApp() async throws {
        try await save(account(id: "acc-a"))
        try await save(multiPlatformApp(id: "app-live", accountId: "acc-a"))
        try await save(multiPlatformApp(id: "app-orphan", accountId: "acc-gone"))
        try await storage.save(review(id: "r-1", appId: "app-live"), id: "r-1")
        try await storage.save(review(id: "r-2", appId: "app-orphan"), id: "r-2")

        let widget = RecentReviewsWidget(configuration: .init(kind: .recentReviews), storage: storage)
        await widget.load()

        XCTAssertEqual(widget.reviews.map(\.id), ["r-1"])
    }

    // MARK: - Guard: never filter without a loaded account list

    /// No accounts stored at all → nothing is filtered. An account-less install is
    /// not a mandate to hide every app.
    func testAwaitingReleaseKeepsAppsWhenNoAccountsExist() async throws {
        try await save(multiPlatformApp(id: "app-1", accountId: "acc-a", awaiting: [version(.ios, .pendingDeveloperRelease, "3.1.0", id: "v-1")]))

        let widget = AwaitingReleaseWidget(configuration: .init(kind: .awaitingRelease), storage: storage)
        await widget.load()

        XCTAssertEqual(widget.apps.map(\.id), ["app-1"])
    }

    /// The account fetch *failing* must not blank out Home either — a transient
    /// storage error would otherwise hide every app on the dashboard.
    func testAwaitingReleaseKeepsAppsWhenAccountFetchFails() async throws {
        let failing = AccountFetchFailingStorage(base: storage)
        try await save(account(id: "acc-a"))
        try await save(multiPlatformApp(id: "app-1", accountId: "acc-a", awaiting: [version(.ios, .pendingDeveloperRelease, "3.1.0", id: "v-1")]))
        try await save(multiPlatformApp(id: "app-orphan", accountId: "acc-gone", awaiting: [version(.ios, .pendingDeveloperRelease, "9.9.9", id: "v-2")]))

        let widget = AwaitingReleaseWidget(configuration: .init(kind: .awaitingRelease), storage: failing)
        await widget.load()

        // Both survive: with no usable account list there is no basis to filter.
        XCTAssertEqual(Set(widget.apps.map(\.id)), ["app-1", "app-orphan"])
    }

    func testInReviewKeepsAppsWhenAccountFetchFails() async throws {
        let failing = AccountFetchFailingStorage(base: storage)
        try await save(multiPlatformApp(id: "app-orphan", accountId: "acc-gone", platformVersions: [version(.ios, .inReview, "9.9.9", id: "v-2")]))

        let widget = InReviewWidget(configuration: .init(kind: .inReview), storage: failing)
        await widget.load()

        XCTAssertEqual(widget.apps.map(\.id), ["app-orphan"])
    }

    // MARK: - filterKnownAccounts (unit)

    func testFilterKnownAccountsDropsOnlyOrphans() {
        let apps = [
            multiPlatformApp(id: "1", accountId: "acc-a"),
            multiPlatformApp(id: "2", accountId: "acc-gone")
        ]
        let map = ["acc-a": account(id: "acc-a")]

        XCTAssertEqual(
            HomeWidgetDataLoader.filterKnownAccounts(apps, accountsMap: map).map(\.id),
            ["1"]
        )
    }

    func testFilterKnownAccountsIsANoOpWithAnEmptyAccountMap() {
        let apps = [
            multiPlatformApp(id: "1", accountId: "acc-a"),
            multiPlatformApp(id: "2", accountId: "acc-gone")
        ]

        XCTAssertEqual(
            HomeWidgetDataLoader.filterKnownAccounts(apps, accountsMap: [:]).map(\.id),
            ["1", "2"]
        )
    }

    // MARK: - Helpers

    private struct AppPlatformVersionKey: Hashable {
        let platform: String?
        let version: String?

        init(platform: String?, version: String?) {
            self.platform = platform
            self.version = version
        }

        init(_ app: AppModel) {
            self.init(platform: app.platform, version: app.versionString)
        }
    }

    private func save(_ account: AccountModel) async throws {
        try await storage.save(account, id: account.id)
    }

    /// Mirrors the production key scheme: apps are stored under
    /// `"{accountId}.{appId}"`, which is why the same app under two accounts
    /// persists as two records rather than upserting into one.
    private func save(_ app: AppModel) async throws {
        try await storage.save(app, id: "\(app.accountId).\(app.id)")
    }

    private func account(id: String) -> AccountModel {
        AccountModel(id: id, name: "Account \(id)", providerType: .apple)
    }

    private func version(
        _ platform: AppPlatform,
        _ state: AppStoreState,
        _ versionString: String,
        id: String
    ) -> AppPlatformVersion {
        AppPlatformVersion(
            platform: platform.rawValue,
            appStoreState: state,
            versionString: versionString,
            id: id
        )
    }

    private func multiPlatformApp(
        id: String,
        accountId: String,
        platformVersions: [AppPlatformVersion]? = nil,
        awaiting: [AppPlatformVersion]? = nil
    ) -> AppModel {
        AppModel(
            id: id,
            name: "App \(id)",
            bundleId: "com.test.\(id)",
            platform: AppPlatform.ios.rawValue,
            accountId: accountId,
            appStoreState: .pendingDeveloperRelease,
            versionString: "3.1.0",
            platformVersions: platformVersions,
            awaitingVersions: awaiting
        )
    }

    private func review(id: String, appId: String) -> CustomerReviewModel {
        CustomerReviewModel(
            id: id,
            rating: 5,
            title: "Title \(id)",
            body: "Body \(id)",
            createdDate: Date(),
            appId: appId
        )
    }
}

// MARK: - Failing storage

/// Delegates everything to a real mock except `fetchAll(AccountModel.self)`,
/// which throws — the transient-failure case the orphan filter must tolerate.
private struct AccountFetchFailingStorage: PersistentStorable {
    let base: MockPersistentStorable

    func save<T: Codable>(_ item: T, id: String) async throws {
        try await base.save(item, id: id)
    }

    func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T? {
        try await base.fetch(type, id: id)
    }

    func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T] {
        if type == AccountModel.self { throw PersistentStorableError.decodingFailed }
        return try await base.fetchAll(type)
    }

    func delete<T: Codable>(_ type: T.Type, id: String) async throws {
        try await base.delete(type, id: id)
    }

    func deleteAll<T: Codable>(_ type: T.Type) async throws {
        try await base.deleteAll(type)
    }
}
