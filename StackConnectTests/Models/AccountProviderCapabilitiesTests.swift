import XCTest
@testable import StackConnect

/// Provider capabilities that drive the export / import / role entry points, and
/// the `AccountModel` helpers built on them.
final class AccountProviderCapabilitiesTests: XCTestCase {

    // MARK: - ProviderType capabilities

    func testSupportsExportPerProvider() {
        XCTAssertTrue(ProviderType.apple.supportsExport)
        XCTAssertTrue(ProviderType.googlePlay.supportsExport)
        XCTAssertFalse(ProviderType.firebase.supportsExport)
    }

    func testSupportsImportPerProvider() {
        XCTAssertTrue(ProviderType.apple.supportsImport)
        XCTAssertTrue(ProviderType.googlePlay.supportsImport)
        XCTAssertFalse(ProviderType.firebase.supportsImport)
    }

    func testSupportsAccountRolePerProvider() {
        XCTAssertTrue(ProviderType.apple.supportsAccountRole)
        XCTAssertTrue(ProviderType.firebase.supportsAccountRole, "Firebase keeps the picker it always had")
        XCTAssertFalse(ProviderType.googlePlay.supportsAccountRole)
    }

    // MARK: - Rule resources per provider

    func testAppleResourcesKeepTheExistingDisplayOrder() {
        XCTAssertEqual(
            AccountRuleResource.resources(for: .apple),
            [.apps, .version, .review, .testFlight, .analytics, .users, .provisioning]
        )
        XCTAssertEqual(Set(AccountRuleResource.resources(for: .apple)), Set(AccountRuleResource.allCases))
    }

    func testGooglePlayResourcesAreAppsVersionsAndReviews() {
        XCTAssertEqual(AccountRuleResource.resources(for: .googlePlay), [.apps, .version, .review, .users])
    }

    /// Play exports written before `.version` was a Play resource carry no
    /// `version` permission: releases stay hidden (fail closed).
    func testOldGooglePlayExportRulesHideReleases() throws {
        let json = #"{"apps":["view","add"],"review":["view","edit"]}"#
        let rules = try JSONDecoder().decode(AccountRules.self, from: Data(json.utf8))
        let account = AccountModel(name: "Imported", providerType: .googlePlay, rules: rules, origin: .imported)

        XCTAssertFalse(account.canView(.version))
        XCTAssertTrue(account.canView(.apps))
        XCTAssertTrue(account.canEdit(.review))
    }

    func testGooglePlayVersionFooterIsWordedForReleases() {
        XCTAssertEqual(
            AccountRuleResource.version.footerDescription(for: .googlePlay),
            String(localized: "View release status, tracks and releases, and manage rollouts")
        )
        XCTAssertEqual(AccountRuleResource.version.footerDescription(for: .apple), AccountRuleResource.version.footerDescription)
        XCTAssertEqual(AccountRuleResource.apps.footerDescription(for: .googlePlay), AccountRuleResource.apps.footerDescription)
    }

    func testFirebaseHasNoResources() {
        XCTAssertTrue(AccountRuleResource.resources(for: .firebase).isEmpty)
    }

    func testAccountRuleResourcesFollowItsProvider() {
        XCTAssertEqual(AccountModel(name: "P", providerType: .googlePlay).ruleResources, [.apps, .version, .review, .users])
        XCTAssertEqual(AccountModel(name: "A", providerType: .apple).ruleResources.count, 7)
    }

    // MARK: - isExportable

    func testCreatedAccountsOfExportableProvidersAreExportable() {
        XCTAssertTrue(AccountModel(name: "A", providerType: .apple).isExportable)
        XCTAssertTrue(AccountModel(name: "P", providerType: .googlePlay).isExportable)
    }

    func testFirebaseAccountIsNotExportable() {
        XCTAssertFalse(AccountModel(name: "F", providerType: .firebase).isExportable)
    }

    func testImportedAccountIsNotExportable() {
        XCTAssertFalse(AccountModel(name: "A", providerType: .apple, origin: .imported).isExportable)
        XCTAssertFalse(AccountModel(name: "P", providerType: .googlePlay, origin: .imported).isExportable)
    }

    // MARK: - displayedRole

    func testDisplayedRoleShowsAppleRole() {
        XCTAssertEqual(AccountModel(name: "A", providerType: .apple, role: .developer).displayedRole, .developer)
    }

    func testDisplayedRoleHidesUnspecified() {
        XCTAssertNil(AccountModel(name: "A", providerType: .apple, role: .unspecified).displayedRole)
    }

    func testDisplayedRoleHidesAnyRoleForGooglePlay() {
        XCTAssertNil(AccountModel(name: "P", providerType: .googlePlay, role: .admin).displayedRole)
    }

    // MARK: - updating(name:role:)

    func testUpdatingKeepsEveryOtherFieldIncludingTheScope() {
        let expiration = Date(timeIntervalSince1970: 2_000_000_000)
        let detectedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let original = AccountModel(
            name: "Old",
            providerType: .googlePlay,
            rules: AccountRules(apps: [.view]),
            origin: .imported,
            role: .unspecified,
            expirationDate: expiration,
            hasPendingAgreements: true,
            pendingAgreementsDetectedAt: detectedAt,
            appsBundles: ["com.a"]
        )

        let renamed = original.updating(name: "New")

        XCTAssertEqual(renamed.name, "New")
        XCTAssertEqual(renamed.id, original.id)
        XCTAssertEqual(renamed.providerType, original.providerType)
        XCTAssertEqual(renamed.createdAt, original.createdAt)
        XCTAssertEqual(renamed.rules, original.rules)
        XCTAssertEqual(renamed.origin, .imported)
        XCTAssertEqual(renamed.role, .unspecified)
        XCTAssertEqual(renamed.expirationDate, expiration)
        XCTAssertTrue(renamed.hasPendingAgreements)
        XCTAssertEqual(renamed.pendingAgreementsDetectedAt, detectedAt)
        XCTAssertEqual(renamed.appsBundles, ["com.a"], "A rename must never widen the per-app scope")
    }

    func testUpdatingRoleOnlyKeepsTheName() {
        let original = AccountModel(name: "Team", providerType: .apple, role: .developer)

        let updated = original.updating(role: .admin)

        XCTAssertEqual(updated.name, "Team")
        XCTAssertEqual(updated.role, .admin)
    }
}
