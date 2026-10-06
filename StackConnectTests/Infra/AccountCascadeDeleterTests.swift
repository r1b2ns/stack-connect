import XCTest
@testable import StackConnect

@MainActor
final class AccountCascadeDeleterTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!

    private let account = AccountModel(name: "Deleted Team", providerType: .apple)
    private let otherAccount = AccountModel(name: "Kept Team", providerType: .apple)

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

    // MARK: - Helpers

    private func deleteAccount() async throws {
        try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)
    }

    /// Saves the account record and its keychain credentials with the app's real keys.
    private func seedAccount(_ account: AccountModel) async throws {
        try await storage.save(account, id: account.id)
        keychain.setObject(
            AppleCredentials(issuerID: "issuer-\(account.id)", privateKeyID: "kid", privateKey: "pk"),
            forKey: "credentials.\(account.id)"
        )
    }

    /// Saves an app under `"<accountId>.<appId>"` plus its versions under `"version.<id>"`.
    @discardableResult
    private func seedApp(
        id: String,
        for account: AccountModel,
        versionIds: [String] = []
    ) async throws -> AppModel {
        let app = AppModel(id: id, name: "App \(id)", bundleId: "com.test.\(id)", accountId: account.id)
        try await storage.save(app, id: "\(account.id).\(app.id)")
        for versionId in versionIds {
            let version = AppStoreVersionModel(id: versionId, appId: app.id)
            try await storage.save(version, id: "version.\(version.id)")
        }
        return app
    }

    @discardableResult
    private func seedTemplate(id: String, for account: AccountModel) async throws -> ReplyTemplateModel {
        let template = ReplyTemplateModel(id: id, accountId: account.id, title: "Title \(id)", body: "Body")
        try await storage.save(template, id: template.id)
        return template
    }

    private func storedTemplateIds() async throws -> Set<String> {
        try await Set(storage.fetchAll(ReplyTemplateModel.self).map(\.id))
    }

    private func storedAppIds() async throws -> Set<String> {
        try await Set(storage.fetchAll(AppModel.self).map(\.id))
    }

    private func storedVersionIds() async throws -> Set<String> {
        try await Set(storage.fetchAll(AppStoreVersionModel.self).map(\.id))
    }

    private func credentials(of account: AccountModel) -> AppleCredentials? {
        keychain.object(forKey: "credentials.\(account.id)")
    }

    // MARK: - Reply templates

    func testDeleteRemovesTheAccountsReplyTemplates() async throws {
        try await seedAccount(account)
        try await seedTemplate(id: "t1", for: account)
        try await seedTemplate(id: "t2", for: account)

        try await deleteAccount()

        let remaining = try await storedTemplateIds()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeleteKeepsAnotherAccountsReplyTemplates() async throws {
        try await seedAccount(account)
        try await seedAccount(otherAccount)
        try await seedTemplate(id: "mine", for: account)
        try await seedTemplate(id: "theirs-1", for: otherAccount)
        try await seedTemplate(id: "theirs-2", for: otherAccount)

        try await deleteAccount()

        let remaining = try await storedTemplateIds()
        XCTAssertEqual(remaining, ["theirs-1", "theirs-2"])
        let keptTemplate = try await storage.fetch(ReplyTemplateModel.self, id: "theirs-1")
        XCTAssertEqual(keptTemplate?.accountId, otherAccount.id)
    }

    // MARK: - Apps, versions, account record, credentials

    func testDeleteRemovesAppsVersionsAccountRecordAndCredentials() async throws {
        try await seedAccount(account)
        try await seedApp(id: "app1", for: account, versionIds: ["v1", "v2"])
        try await seedApp(id: "app2", for: account, versionIds: ["v3"])

        try await deleteAccount()

        let remainingApps = try await storedAppIds()
        let remainingVersions = try await storedVersionIds()
        let storedAccount = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertTrue(remainingApps.isEmpty)
        XCTAssertTrue(remainingVersions.isEmpty)
        XCTAssertNil(storedAccount)
        XCTAssertNil(credentials(of: account))
    }

    func testDeleteLeavesAnotherAccountsAppsVersionsRecordAndCredentials() async throws {
        try await seedAccount(account)
        try await seedAccount(otherAccount)
        try await seedApp(id: "mine", for: account, versionIds: ["v-mine"])
        try await seedApp(id: "theirs", for: otherAccount, versionIds: ["v-theirs"])

        try await deleteAccount()

        let remainingApps = try await storedAppIds()
        let remainingVersions = try await storedVersionIds()
        let keptApp = try await storage.fetch(AppModel.self, id: "\(otherAccount.id).theirs")
        let keptAccount = try await storage.fetch(AccountModel.self, id: otherAccount.id)
        XCTAssertEqual(remainingApps, ["theirs"])
        XCTAssertEqual(remainingVersions, ["v-theirs"])
        XCTAssertNotNil(keptApp)
        XCTAssertNotNil(keptAccount)
        XCTAssertEqual(credentials(of: otherAccount)?.issuerID, "issuer-\(otherAccount.id)")
    }

    func testDeleteReadsVersionsOnceRegardlessOfAppCount() async throws {
        try await seedAccount(account)
        try await seedApp(id: "app1", for: account, versionIds: ["v1"])
        try await seedApp(id: "app2", for: account, versionIds: ["v2"])
        try await seedApp(id: "app3", for: account, versionIds: ["v3"])

        try await deleteAccount()

        let versionReads = await storage.fetchAllCallCount["AppStoreVersionModel"]
        XCTAssertEqual(versionReads, 1)
    }

    func testDeleteAccountWithoutAppsSkipsVersionsRead() async throws {
        try await seedAccount(account)
        try await seedApp(id: "theirs", for: otherAccount, versionIds: ["v-theirs"])

        try await deleteAccount()

        let versionReads = await storage.fetchAllCallCount["AppStoreVersionModel", default: 0]
        let storedAccount = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(versionReads, 0)
        XCTAssertNil(storedAccount)
    }

    // MARK: - Google Play app cache

    private func seedGooglePlayCache(for account: AccountModel, packageNames: [String]) async throws {
        let apps = packageNames.map {
            GooglePlayAppItem(id: $0, packageName: $0, title: nil, isManuallyAdded: false)
        }
        try await storage.save(apps, id: GooglePlayAppItem.cacheKey(accountId: account.id))
    }

    private func googlePlayCache(of account: AccountModel) async throws -> [GooglePlayAppItem]? {
        try await storage.fetch([GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: account.id))
    }

    func testDeleteRemovesTheGooglePlayAppCacheAndKeepsOtherAccounts() async throws {
        let playAccount = AccountModel(name: "Play Team", providerType: .googlePlay)
        let otherPlayAccount = AccountModel(name: "Other Play Team", providerType: .googlePlay)
        try await storage.save(playAccount, id: playAccount.id)
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: "{}"), forKey: "credentials.\(playAccount.id)")
        try await seedGooglePlayCache(for: playAccount, packageNames: ["com.mine.app"])
        try await seedGooglePlayCache(for: otherPlayAccount, packageNames: ["com.theirs.app"])

        try await AccountCascadeDeleter.delete(playAccount, storage: storage, keychain: keychain)

        let deletedCache = try await googlePlayCache(of: playAccount)
        let keptCache = try await googlePlayCache(of: otherPlayAccount)
        let storedAccount = try await storage.fetch(AccountModel.self, id: playAccount.id)
        let credentials: GooglePlayCredentials? = keychain.object(forKey: "credentials.\(playAccount.id)")
        XCTAssertNil(deletedCache)
        XCTAssertEqual(keptCache?.map(\.packageName), ["com.theirs.app"])
        XCTAssertNil(storedAccount)
        XCTAssertNil(credentials)
    }

    func testGooglePlayCacheDeleteFailureDoesNotStopTheCascade() async throws {
        let playAccount = AccountModel(name: "Play Team", providerType: .googlePlay)
        try await storage.save(playAccount, id: playAccount.id)
        try await seedGooglePlayCache(for: playAccount, packageNames: ["com.mine.app"])
        await storage.failDelete([GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: playAccount.id))

        try await AccountCascadeDeleter.delete(playAccount, storage: storage, keychain: keychain)

        let storedAccount = try await storage.fetch(AccountModel.self, id: playAccount.id)
        XCTAssertNil(storedAccount)
    }

    // MARK: - Google Play per-app caches (app details, listings, tracks, reviews)

    private func seedGooglePlaySections(for account: AccountModel, packageName: String) async throws {
        let details = GooglePlayAppDetailsCache(
            accountId: account.id,
            packageName: packageName,
            details: GooglePlayAppDetailsModel(packageName: packageName, defaultLanguage: "en-US")
        )
        let listings = GooglePlayStoreListingsCache(
            accountId: account.id,
            packageName: packageName,
            listings: [GooglePlayStoreListingModel(language: "en-US", title: "T", shortDescription: nil, fullDescription: nil, video: nil)]
        )
        let tracks = GooglePlayTracksCache(
            accountId: account.id,
            packageName: packageName,
            tracks: [GooglePlayTrackModel(track: "production", releases: [])]
        )
        let reviews = GooglePlayReviewsCache(
            accountId: account.id,
            packageName: packageName,
            reviews: [CustomerReviewModel(id: "\(packageName)/r1", rating: 5)]
        )
        try await storage.save(details, id: details.cacheKey)
        try await storage.save(listings, id: listings.cacheKey)
        try await storage.save(tracks, id: tracks.cacheKey)
        try await storage.save(reviews, id: reviews.cacheKey)
    }

    /// Package names with at least one cached section for `account`, per section.
    private func googlePlaySectionPackages(of account: AccountModel) async throws -> [String: Set<String>] {
        func packages<T: GooglePlayAppScopedCache>(_ type: T.Type) async throws -> Set<String> {
            try await Set(storage.fetchAll(T.self).filter { $0.accountId == account.id }.map(\.packageName))
        }
        return try await [
            "details": packages(GooglePlayAppDetailsCache.self),
            "listings": packages(GooglePlayStoreListingsCache.self),
            "tracks": packages(GooglePlayTracksCache.self),
            "reviews": packages(GooglePlayReviewsCache.self)
        ]
    }

    func testDeleteRemovesEveryGooglePlaySectionCacheIncludingAppsNoLongerListed() async throws {
        let playAccount = AccountModel(name: "Play Team", providerType: .googlePlay)
        try await storage.save(playAccount, id: playAccount.id)
        try await seedGooglePlayCache(for: playAccount, packageNames: ["com.listed.app"])
        try await seedGooglePlaySections(for: playAccount, packageName: "com.listed.app")
        // An app removed from the list (e.g. a manual app) still has caches.
        try await seedGooglePlaySections(for: playAccount, packageName: "com.removed.app")

        try await AccountCascadeDeleter.delete(playAccount, storage: storage, keychain: keychain)

        let remaining = try await googlePlaySectionPackages(of: playAccount)
        XCTAssertEqual(remaining, ["details": [], "listings": [], "tracks": [], "reviews": []])
    }

    func testDeleteKeepsAnotherGooglePlayAccountsSectionCaches() async throws {
        let playAccount = AccountModel(name: "Play Team", providerType: .googlePlay)
        let otherPlayAccount = AccountModel(name: "Other Play Team", providerType: .googlePlay)
        try await storage.save(playAccount, id: playAccount.id)
        try await seedGooglePlaySections(for: playAccount, packageName: "com.shared.app")
        try await seedGooglePlaySections(for: otherPlayAccount, packageName: "com.shared.app")

        try await AccountCascadeDeleter.delete(playAccount, storage: storage, keychain: keychain)

        let kept = try await googlePlaySectionPackages(of: otherPlayAccount)
        let expected: Set<String> = ["com.shared.app"]
        XCTAssertEqual(kept, ["details": expected, "listings": expected, "tracks": expected, "reviews": expected])
    }

    func testGooglePlaySectionDeleteFailureDoesNotStopTheCascade() async throws {
        let playAccount = AccountModel(name: "Play Team", providerType: .googlePlay)
        try await storage.save(playAccount, id: playAccount.id)
        try await seedGooglePlaySections(for: playAccount, packageName: "com.mine.app")
        await storage.failDelete(
            GooglePlayTracksCache.self,
            id: GooglePlayTracksCache.cacheKey(accountId: playAccount.id, packageName: "com.mine.app")
        )

        try await AccountCascadeDeleter.delete(playAccount, storage: storage, keychain: keychain)

        let remaining = try await googlePlaySectionPackages(of: playAccount)
        let storedAccount = try await storage.fetch(AccountModel.self, id: playAccount.id)
        XCTAssertEqual(remaining["tracks"], ["com.mine.app"], "Only the failing entry stays")
        XCTAssertEqual(remaining["details"], [])
        XCTAssertEqual(remaining["reviews"], [])
        XCTAssertNil(storedAccount)
    }

    func testGooglePlaySectionReadFailurePropagatesBeforeAnythingIsDeleted() async throws {
        let playAccount = AccountModel(name: "Play Team", providerType: .googlePlay)
        try await storage.save(playAccount, id: playAccount.id)
        try await seedGooglePlaySections(for: playAccount, packageName: "com.mine.app")
        await storage.failFetchAll(GooglePlayReviewsCache.self)

        do {
            try await AccountCascadeDeleter.delete(playAccount, storage: storage, keychain: keychain)
            XCTFail("Expected the reviews cache read failure to propagate")
        } catch {
            XCTAssertTrue(error is MockPersistentStorable.InjectedFailure)
        }

        let details = try await storage.fetch(
            GooglePlayAppDetailsCache.self,
            id: GooglePlayAppDetailsCache.cacheKey(accountId: playAccount.id, packageName: "com.mine.app")
        )
        let storedAccount = try await storage.fetch(AccountModel.self, id: playAccount.id)
        XCTAssertNotNil(details)
        XCTAssertNotNil(storedAccount)
    }

    func testAppleAccountDeleteSkipsTheGooglePlaySectionReads() async throws {
        try await seedAccount(account)

        try await deleteAccount()

        let reads = await storage.fetchAllCallCount["GooglePlayAppDetailsCache", default: 0]
        XCTAssertEqual(reads, 0)
    }

    // MARK: - Error semantics

    func testChildDeleteFailureDoesNotStopTheCascade() async throws {
        try await seedAccount(account)
        try await seedApp(id: "app1", for: account, versionIds: ["v1"])
        try await seedApp(id: "app2", for: account, versionIds: ["v2"])
        try await seedTemplate(id: "stuck", for: account)
        try await seedTemplate(id: "t2", for: account)
        await storage.failDelete(AppModel.self, id: "\(account.id).app1")
        await storage.failDelete(ReplyTemplateModel.self, id: "stuck")

        try await deleteAccount()

        // The failing children stay; everything else is still removed.
        let remainingApps = try await storedAppIds()
        let remainingVersions = try await storedVersionIds()
        let remainingTemplates = try await storedTemplateIds()
        let storedAccount = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(remainingApps, ["app1"])
        XCTAssertTrue(remainingVersions.isEmpty)
        XCTAssertEqual(remainingTemplates, ["stuck"])
        XCTAssertNil(storedAccount)
        XCTAssertNil(credentials(of: account))
    }

    func testAccountRecordDeleteFailurePropagatesAndKeepsCredentials() async throws {
        try await seedAccount(account)
        try await seedApp(id: "app1", for: account)
        try await seedTemplate(id: "t1", for: account)
        await storage.failDelete(AccountModel.self, id: account.id)

        do {
            try await deleteAccount()
            XCTFail("Expected the AccountModel delete failure to propagate")
        } catch {
            XCTAssertTrue(error is MockPersistentStorable.InjectedFailure)
        }

        let storedAccount = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertNotNil(storedAccount)
        XCTAssertNotNil(credentials(of: account))
    }

    func testReadFailurePropagatesBeforeAnythingIsDeleted() async throws {
        try await seedAccount(account)
        try await seedApp(id: "app1", for: account, versionIds: ["v1"])
        try await seedTemplate(id: "t1", for: account)
        await storage.failFetchAll(ReplyTemplateModel.self)

        do {
            try await deleteAccount()
            XCTFail("Expected the reply templates read failure to propagate")
        } catch {
            XCTAssertTrue(error is MockPersistentStorable.InjectedFailure)
        }

        let remainingApps = try await storedAppIds()
        let remainingVersions = try await storedVersionIds()
        let storedTemplate = try await storage.fetch(ReplyTemplateModel.self, id: "t1")
        let storedAccount = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(remainingApps, ["app1"])
        XCTAssertEqual(remainingVersions, ["v1"])
        XCTAssertNotNil(storedTemplate)
        XCTAssertNotNil(storedAccount)
        XCTAssertNotNil(credentials(of: account))
    }
}
