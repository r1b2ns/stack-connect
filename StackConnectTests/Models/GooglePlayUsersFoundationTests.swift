import XCTest
import StackCoreRust
@testable import StackConnect

/// Models, permission catalog, presets, developer ID, error copy and cache
/// lifetime of the Google Play users feature (plan section 7, task U1).
@MainActor
final class GooglePlayUsersFoundationTests: XCTestCase {

    private typealias Catalog = GooglePlayPermissionCatalog

    // MARK: - Access state

    func testAccessStateIsUnknownSafe() {
        XCTAssertEqual(GooglePlayUserAccessState(rawValue: "INVITED"), .invited)
        XCTAssertEqual(GooglePlayUserAccessState(rawValue: "INVITATION_EXPIRED"), .invitationExpired)
        XCTAssertEqual(GooglePlayUserAccessState(rawValue: "ACCESS_GRANTED"), .accessGranted)
        XCTAssertEqual(GooglePlayUserAccessState(rawValue: "ACCESS_EXPIRED"), .accessExpired)
        XCTAssertEqual(GooglePlayUserAccessState(rawValue: "SOMETHING_NEW"), .unknown("SOMETHING_NEW"))
        XCTAssertEqual(GooglePlayUserAccessState(rawValue: "SOMETHING_NEW").rawValue, "SOMETHING_NEW", "The raw value survives a save")
    }

    // MARK: - User

    func testDisplayNameAndInitials() {
        XCTAssertEqual(GooglePlayUserModel(email: "dana.whitfield@northwind.example").displayName, "Dana Whitfield")
        XCTAssertEqual(GooglePlayUserModel(email: "dana.whitfield@northwind.example").initials, "DW")
        XCTAssertEqual(GooglePlayUserModel(email: "support@northwind.example").displayName, "Support")
        XCTAssertEqual(GooglePlayUserModel(email: "support@northwind.example").initials, "SU")

        let invited = GooglePlayUserModel(email: "kai@contractor.example", accessState: .invited)
        XCTAssertEqual(invited.displayName, "kai@contractor.example", "Google only learns the name once the invitation is accepted")

        let service = GooglePlayUserModel(email: "ci-publisher@nw-play.iam.gserviceaccount.com")
        XCTAssertTrue(service.isServiceAccount)
        XCTAssertEqual(service.displayName, "ci-publisher")
        XCTAssertEqual(service.initials, "ci")
        XCTAssertFalse(GooglePlayUserModel(email: "person@gmail.com").isServiceAccount)
    }

    func testMapsTheCoreUser() {
        let info = PlayUserInfo(
            email: "a@b.example", name: "developers/1/users/a@b.example", accessState: "INVITED",
            expirationTime: "2026-12-31T00:00:00Z", developerAccountPermissions: ["CAN_REPLY_TO_REVIEWS_GLOBAL"],
            grants: [PlayGrantInfo(packageName: "com.x", appLevelPermissions: ["CAN_REPLY_TO_REVIEWS"])], partial: true
        )

        let user = GooglePlayAccountConnection.mapUser(info)

        XCTAssertEqual(user.accessState, .invited)
        XCTAssertEqual(user.expirationTime, ISO8601DateFormatter().date(from: "2026-12-31T00:00:00Z"))
        XCTAssertEqual(user.grants, [GooglePlayGrantModel(packageName: "com.x", appLevelPermissions: ["CAN_REPLY_TO_REVIEWS"])])
        XCTAssertTrue(user.partial)
        XCTAssertNotNil(GooglePlayAccountConnection.parseExpiration("2026-12-31T00:00:00.123Z"), "Fractional seconds parse too")
    }

    // MARK: - Catalog

    func testCatalogCoversEveryGooglePermission() {
        // The non-deprecated values of the Android Publisher v3 discovery document.
        let account: Set<String> = [
            "CAN_VIEW_FINANCIAL_DATA_GLOBAL", "CAN_EDIT_GAMES_GLOBAL", "CAN_PUBLISH_GAMES_GLOBAL",
            "CAN_REPLY_TO_REVIEWS_GLOBAL", "CAN_MANAGE_PUBLIC_APKS_GLOBAL", "CAN_MANAGE_TRACK_APKS_GLOBAL",
            "CAN_MANAGE_TRACK_USERS_GLOBAL", "CAN_MANAGE_PUBLIC_LISTING_GLOBAL", "CAN_MANAGE_DRAFT_APPS_GLOBAL",
            "CAN_CREATE_MANAGED_PLAY_APPS_GLOBAL", "CAN_MANAGE_ORDERS_GLOBAL", "CAN_MANAGE_APP_CONTENT_GLOBAL",
            "CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_VIEW_APP_QUALITY_GLOBAL", "CAN_MANAGE_DEEPLINKS_GLOBAL",
            "CAN_VIEW_CONNECTED_APPS_GLOBAL", "CAN_EDIT_CONNECTED_APPS_GLOBAL"
        ]
        let app: Set<String> = [
            "CAN_VIEW_FINANCIAL_DATA", "CAN_MANAGE_PERMISSIONS", "CAN_REPLY_TO_REVIEWS", "CAN_MANAGE_PUBLIC_APKS",
            "CAN_MANAGE_TRACK_APKS", "CAN_MANAGE_TRACK_USERS", "CAN_MANAGE_PUBLIC_LISTING", "CAN_MANAGE_DRAFT_APPS",
            "CAN_MANAGE_ORDERS", "CAN_MANAGE_APP_CONTENT", "CAN_VIEW_NON_FINANCIAL_DATA", "CAN_VIEW_APP_QUALITY",
            "CAN_MANAGE_DEEPLINKS"
        ]
        XCTAssertEqual(Set(Catalog.accountPermissions.compactMap(\.accountLevel)), account)
        XCTAssertEqual(Set(Catalog.appPermissions.compactMap(\.appLevel)), app)
        XCTAssertEqual(Set(Catalog.all.map(\.id)).count, Catalog.all.count, "Stable ids are unique")
        XCTAssertEqual(Catalog.grouped(.app).map(\.group), GooglePlayPermissionGroup.allCases)
    }

    func testLegacyValuesReadAsViewAppInformation() {
        XCTAssertTrue(Catalog.contains(Catalog.viewAppInformation, in: ["CAN_SEE_ALL_APPS"], level: .account))
        XCTAssertTrue(Catalog.contains(Catalog.viewAppInformation, in: ["CAN_ACCESS_APP"], level: .app))
        XCTAssertTrue(Catalog.unknownValues(in: ["CAN_SEE_ALL_APPS", "CAN_ACCESS_APP"]).isEmpty)
    }

    func testUnknownPermissionsSurviveARoundTrip() {
        let original = ["CAN_CHANGE_MANAGED_PLAY_SETTING_GLOBAL", "CAN_REPLY_TO_REVIEWS_GLOBAL", "CAN_SOMETHING_NEW_GLOBAL"]
        let reply = Catalog.all.first { $0.id == "replyToReviews" }!
        let financial = Catalog.all.first { $0.id == "viewFinancialData" }!

        var edited = Catalog.setting(reply, on: false, in: original, level: .account)
        edited = Catalog.setting(financial, on: true, in: edited, level: .account)
        let saved = Catalog.normalized(edited, level: .account)

        XCTAssertTrue(saved.contains("CAN_CHANGE_MANAGED_PLAY_SETTING_GLOBAL"))
        XCTAssertTrue(saved.contains("CAN_SOMETHING_NEW_GLOBAL"))
        XCTAssertFalse(saved.contains("CAN_REPLY_TO_REVIEWS_GLOBAL"))
        XCTAssertTrue(saved.contains("CAN_VIEW_FINANCIAL_DATA_GLOBAL"))
        XCTAssertEqual(Catalog.unknownValues(in: saved), ["CAN_CHANGE_MANAGED_PLAY_SETTING_GLOBAL", "CAN_SOMETHING_NEW_GLOBAL"])
        XCTAssertEqual(Catalog.displayName(forUnknown: "CAN_CHANGE_MANAGED_PLAY_SETTING_GLOBAL"), "Change managed play setting")
    }

    func testAnyPermissionImpliesViewAppInformation() {
        XCTAssertEqual(Catalog.normalized(["CAN_REPLY_TO_REVIEWS"], level: .app), ["CAN_VIEW_NON_FINANCIAL_DATA", "CAN_REPLY_TO_REVIEWS"])
        XCTAssertEqual(Catalog.normalized([], level: .app), [], "No permission stays empty")
        XCTAssertEqual(Catalog.normalized(["CAN_ACCESS_APP"], level: .app), ["CAN_ACCESS_APP"], "A legacy view value is enough")
        XCTAssertEqual(Catalog.accountState(of: Catalog.viewAppInformation, in: ["CAN_REPLY_TO_REVIEWS_GLOBAL"]), .implied)
        XCTAssertEqual(Catalog.accountState(of: Catalog.viewAppInformation, in: ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL"]), .on)
    }

    func testAdminImpliesEverything() {
        let reply = Catalog.all.first { $0.id == "replyToReviews" }!
        XCTAssertEqual(Catalog.accountState(of: reply, in: [Catalog.adminPermission]), .implied)
        XCTAssertEqual(Catalog.appState(of: reply, appValues: [], accountValues: [Catalog.adminPermission]), .implied)
        XCTAssertEqual(Catalog.appState(of: reply, appValues: [Catalog.appAdminPermission], accountValues: []), .implied,
                       "The app-level admin implies every permission of that app")
        XCTAssertEqual(Catalog.appState(of: Catalog.manageUsers, appValues: [Catalog.appAdminPermission], accountValues: []), .on)
    }

    func testAccountPermissionsLockTheSameAppPermission() {
        let reply = Catalog.all.first { $0.id == "replyToReviews" }!
        let production = Catalog.all.first { $0.id == "releaseToProduction" }!

        XCTAssertEqual(Catalog.appState(of: reply, appValues: [], accountValues: ["CAN_REPLY_TO_REVIEWS_GLOBAL"]), .implied)
        XCTAssertEqual(Catalog.appState(of: production, appValues: [], accountValues: ["CAN_REPLY_TO_REVIEWS_GLOBAL"]), .off)
        XCTAssertEqual(Catalog.appState(of: Catalog.viewAppInformation, appValues: [], accountValues: ["CAN_REPLY_TO_REVIEWS_GLOBAL"]), .implied)
    }

    func testSummary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Catalog.summary(for: GooglePlayUserModel(email: "a@x.example", developerAccountPermissions: [Catalog.adminPermission])),
                       "Admin (all permissions)")
        let support = GooglePlayUserModel(email: "s@x.example", grants: [
            GooglePlayGrantModel(packageName: "com.a", appLevelPermissions: ["CAN_VIEW_NON_FINANCIAL_DATA", "CAN_REPLY_TO_REVIEWS"])
        ])
        // Granted: the "1 App" badge carries the scope, so the line doesn't repeat it.
        XCTAssertEqual(Catalog.summary(for: support), "Reply to reviews")
        XCTAssertEqual(support.listBadge?.title, "1 App")
        var invited = support
        invited.accessStateRaw = GooglePlayUserAccessState.invited.rawValue
        // Invited: the badge shows the state, so the line keeps the app count.
        XCTAssertEqual(Catalog.summary(for: invited), "Reply to reviews · 1 app")
        let releases = GooglePlayUserModel(email: "r@x.example", grants: [
            GooglePlayGrantModel(packageName: "com.a", appLevelPermissions: ["CAN_MANAGE_PUBLIC_APKS", "CAN_MANAGE_PUBLIC_LISTING"]),
            GooglePlayGrantModel(packageName: "com.b", appLevelPermissions: ["CAN_MANAGE_TRACK_APKS"])
        ])
        XCTAssertEqual(Catalog.summary(for: releases), "Releases, Store presence")
        XCTAssertEqual(releases.listBadge?.title, "2 Apps")
        let service = GooglePlayUserModel(email: "ci@p.iam.gserviceaccount.com", developerAccountPermissions: ["CAN_MANAGE_TRACK_APKS_GLOBAL"])
        XCTAssertEqual(Catalog.summary(for: service), "Service account · Release to testing tracks")
        let expiring = GooglePlayUserModel(email: "e@x.example", expirationTime: now.addingTimeInterval(86_400),
                                           developerAccountPermissions: ["CAN_REPLY_TO_REVIEWS_GLOBAL"])
        XCTAssertTrue(Catalog.summary(for: expiring, now: now).hasPrefix("Reply to reviews · expires "))
    }

    // MARK: - Presets

    func testPresetsOnlyPrefillAccountPermissions() {
        XCTAssertEqual(GooglePlayPermissionPreset.admin.accountPermissions, [Catalog.adminPermission])
        XCTAssertNil(GooglePlayPermissionPreset.custom.accountPermissions, "Custom keeps the toggles as they are")
        XCTAssertEqual(GooglePlayPermissionPreset.matching(["CAN_REPLY_TO_REVIEWS_GLOBAL"]), .support, "Matched after normalization")
        XCTAssertEqual(GooglePlayPermissionPreset.matching(["CAN_REPLY_TO_REVIEWS_GLOBAL", "CAN_MANAGE_ORDERS_GLOBAL"]), .custom)
        for preset in GooglePlayPermissionPreset.allCases {
            for value in preset.accountPermissions ?? [] {
                XCTAssertTrue(value == Catalog.adminPermission || Catalog.permission(forValue: value) != nil, "\(value) is in the catalog")
            }
        }
    }

    // MARK: - Developer ID

    func testDeveloperIdNormalization() {
        XCTAssertEqual(GooglePlayDeveloperId.normalized(" 4829103756618820931 "), "4829103756618820931")
        XCTAssertEqual(
            GooglePlayDeveloperId.normalized("https://play.google.com/console/u/0/developers/4829103756618820931/app-list"),
            "4829103756618820931"
        )
        XCTAssertNil(GooglePlayDeveloperId.normalized("northwind"))
        XCTAssertNil(GooglePlayDeveloperId.normalized(""))
        XCTAssertTrue(GooglePlayDeveloperId.isAcceptable(""), "The field is optional")
        XCTAssertFalse(GooglePlayDeveloperId.isAcceptable("12a"))
    }

    func testDeveloperIdSurvivesRenameAndDecoding() throws {
        let account = AccountModel(name: "Play", providerType: .googlePlay, googlePlayDeveloperId: "123")
        XCTAssertEqual(account.updating(name: "Renamed").googlePlayDeveloperId, "123")
        XCTAssertNil(account.updating(googlePlayDeveloperId: .some(nil)).googlePlayDeveloperId)

        let decoded = try JSONDecoder().decode(AccountModel.self, from: JSONEncoder().encode(account))
        XCTAssertEqual(decoded.googlePlayDeveloperId, "123")
    }

    // MARK: - Rules

    func testGooglePlayRulesIncludeUsers() {
        XCTAssertEqual(AccountRuleResource.resources(for: .googlePlay), [.apps, .version, .review, .users])
        XCTAssertTrue(AccountModel(name: "Play", providerType: .googlePlay).canAdd(.users), "Accounts created here get every permission")
        XCTAssertFalse(
            AccountModel(name: "Old", providerType: .googlePlay, rules: AccountRules(apps: [.view]), origin: .imported).canView(.users),
            "An older export has no `users` permission: the tab is hidden"
        )
        XCTAssertNotEqual(AccountRuleResource.users.footerDescription(for: .googlePlay), AccountRuleResource.users.footerDescription)
    }

    // MARK: - Error copy

    func testUsersErrorCopy() {
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 404, message: "x"), operation: .users),
            String(localized: "Google Play found no developer account with this ID. Check the Developer ID in Play Console › Settings › Developer account.")
        )
        XCTAssertTrue(GooglePlayErrorTranslator.isWrongDeveloperId(StackError.Http(status: 404, message: "")))
        XCTAssertFalse(GooglePlayErrorTranslator.isWrongDeveloperId(StackError.Network(message: "")))

        let auth = GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: "Needs Admin (all permissions)."), operation: .users)
        XCTAssertTrue(auth.hasPrefix(String(localized: "To manage users, this service account needs the “Admin (all permissions)” permission in Play Console › Users and permissions.")))
        XCTAssertTrue(auth.hasSuffix("Needs Admin (all permissions)."))

        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 409, message: "exists"), operation: .inviteUser),
            String(localized: "This person already has access to this developer account or has a pending invitation.")
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 400, message: "The email is not a valid Google Account."), operation: .inviteUser),
            String(localized: "Google Play can only invite Google accounts. Check the address, or ask the person which Google account (Gmail or Google Workspace) to use.")
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 404, message: ""), operation: .userChange),
            String(localized: "This user or app access is no longer on Google Play. Refresh and try again.")
        )
    }

    // MARK: - Cache lifetime

    func testCascadeDeleteRemovesTheUsersCache() async throws {
        let storage = MockPersistentStorable()
        let keychain = MockKeyStorable()
        let account = AccountModel(name: "Play", providerType: .googlePlay)
        let other = AccountModel(name: "Other", providerType: .googlePlay)
        try await storage.save(account, id: account.id)
        for owner in [account, other] {
            let cache = GooglePlayUsersCache(accountId: owner.id, users: [GooglePlayUserModel(email: "a@x.example")], fetchedAt: Date())
            try await storage.save(cache, id: cache.cacheKey)
        }

        try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)

        let deleted = try await storage.fetch(GooglePlayUsersCache.self, id: GooglePlayUsersCache.cacheKey(accountId: account.id))
        let kept = try await storage.fetch(GooglePlayUsersCache.self, id: GooglePlayUsersCache.cacheKey(accountId: other.id))
        XCTAssertNil(deleted)
        XCTAssertNotNil(kept)
    }

    // MARK: - Add Account / Account Settings

    func testAddAccountSavesTheOptionalDeveloperId() async throws {
        let storage = MockPersistentStorable()
        let sut = AddAccountViewModel(
            providerType: .googlePlay, storage: storage, keychain: MockKeyStorable(),
            googlePlayConnectionFactory: { _ in MockGooglePlayAccountConnection() }
        )
        sut.uiState.accountName = "Play"
        sut.uiState.googlePlayJSON = GooglePlayTestFixtures.serviceAccountJSON()
        sut.uiState.googlePlayDeveloperId = "https://play.google.com/console/u/0/developers/987654321/app-list"

        await sut.save()

        XCTAssertTrue(sut.uiState.isSaved)
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(saved.first?.googlePlayDeveloperId, "987654321")
    }

    func testAddAccountRejectsAnInvalidDeveloperIdAndSavesNothing() async throws {
        let storage = MockPersistentStorable()
        let sut = AddAccountViewModel(
            providerType: .googlePlay, storage: storage, keychain: MockKeyStorable(),
            googlePlayConnectionFactory: { _ in MockGooglePlayAccountConnection() }
        )
        sut.uiState.accountName = "Play"
        sut.uiState.googlePlayJSON = GooglePlayTestFixtures.serviceAccountJSON()
        sut.uiState.googlePlayDeveloperId = "northwind"

        await sut.save()

        XCTAssertFalse(sut.uiState.isSaved)
        XCTAssertNotNil(sut.uiState.validationError)
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertTrue(saved.isEmpty)
    }

    func testAddAccountWithoutDeveloperIdStillSaves() async throws {
        let storage = MockPersistentStorable()
        let sut = AddAccountViewModel(
            providerType: .googlePlay, storage: storage, keychain: MockKeyStorable(),
            googlePlayConnectionFactory: { _ in MockGooglePlayAccountConnection() }
        )
        sut.uiState.accountName = "Play"
        sut.uiState.googlePlayJSON = GooglePlayTestFixtures.serviceAccountJSON()

        await sut.save()

        XCTAssertTrue(sut.uiState.isSaved)
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertNil(saved.first?.googlePlayDeveloperId)
    }

    func testAccountSettingsEditsTheDeveloperId() async throws {
        let storage = MockPersistentStorable()
        let account = AccountModel(name: "Play", providerType: .googlePlay)
        let sut = AccountSettingsViewModel(account: account, storage: storage, keychain: MockKeyStorable())

        sut.uiState.editingDeveloperId = "123456"
        await sut.saveDeveloperId()
        XCTAssertEqual(sut.uiState.account.googlePlayDeveloperId, "123456")
        let stored = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(stored?.googlePlayDeveloperId, "123456")

        sut.uiState.editingDeveloperId = "abc"
        await sut.saveDeveloperId()
        XCTAssertEqual(sut.uiState.account.googlePlayDeveloperId, "123456", "An invalid ID changes nothing")

        sut.uiState.editingDeveloperId = ""
        await sut.saveDeveloperId()
        XCTAssertNil(sut.uiState.account.googlePlayDeveloperId, "An empty field clears it")
    }
}
