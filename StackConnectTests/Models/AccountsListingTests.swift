import XCTest
@testable import StackConnect

/// The single rule of the unified accounts lists: grouping, search and the
/// Summary of the Accounts rows.
final class AccountsListingTests: XCTestCase {

    private let accounts = [
        AccountModel(id: "1", name: "Acme Apps", providerType: .apple),
        AccountModel(id: "2", name: "Personal", providerType: .apple, authMethod: .appleIdSignIn),
        AccountModel(id: "3", name: "Client North", providerType: .googlePlay, authMethod: .googleSignIn),
        AccountModel(id: "4", name: "acme-prod", providerType: .firebase),
        AccountModel(id: "5", name: "Ação", providerType: .firebase)
    ]

    func testGroupsFollowTheListOrderAndSkipEmptyOrUnavailableStores() {
        let groups = AccountsListing.groups(of: accounts, providers: [.firebase, .apple])

        XCTAssertEqual(groups.map(\.provider), [.apple, .firebase])
        XCTAssertEqual(groups.last?.accounts.map(\.name), ["Ação", "acme-prod"])
    }

    func testSearchIgnoresCaseAndDiacritics() {
        let groups = AccountsListing.groups(of: accounts, providers: ProviderType.allCases)

        XCTAssertEqual(AccountsListing.filter(groups, query: "ACAO").flatMap(\.accounts).map(\.id), ["5"])
        XCTAssertEqual(AccountsListing.filter(groups, query: " firebase ").flatMap(\.accounts).map(\.id), ["5", "4"])
        XCTAssertTrue(AccountsListing.matches(accounts[0], query: ""))
        XCTAssertFalse(AccountsListing.matches(accounts[0], query: "google"))
    }

    func testSummaryCountsTotalAttentionAndStores() {
        let statuses: [String: AccountStatus] = [
            "2": .of(.signInExpired),
            "3": .of(.pendingAgreements),
            "4": .of(.signInReconnecting)
        ]

        let summary = AccountsSummary(accounts: accounts, statuses: statuses, providers: ProviderType.allCases)

        XCTAssertEqual(summary.total, 5)
        XCTAssertEqual(summary.needsAttention, 3)
        XCTAssertEqual(summary.providers, [
            .init(provider: .apple, count: 2),
            .init(provider: .googlePlay, count: 1),
            .init(provider: .firebase, count: 2)
        ])
    }

    func testSummaryLeavesHiddenStoresOut() {
        let summary = AccountsSummary(accounts: accounts, statuses: ["3": .of(.signInExpired)], providers: [.apple, .firebase])

        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.needsAttention, 0, "A hidden account's status isn't counted")
        XCTAssertEqual(summary.providers.map(\.provider), [.apple, .firebase])
    }

    // MARK: - Count title

    func testCountTitleUsesADedicatedStringForZero() {
        // CLDR puts 0 in "one" in pt-BR: the plural string would read "0 conta".
        XCTAssertEqual(StackAccountGroupHeader.countTitle(0), String(localized: "No accounts"))
        XCTAssertFalse(StackAccountGroupHeader.countTitle(0).contains("0"))
        XCTAssertEqual(AccountsSummary.empty.total, 0)
    }

    func testCountTitleKeepsThePluralForPositiveCounts() {
        XCTAssertNotEqual(StackAccountGroupHeader.countTitle(1), String(localized: "No accounts"))
        XCTAssertTrue(StackAccountGroupHeader.countTitle(1).contains("1"))
        XCTAssertTrue(StackAccountGroupHeader.countTitle(3).contains("3"))
    }

    func testZeroCountIsTranslatedToPortuguese() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "pt-BR", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))

        XCTAssertEqual(String(localized: "No accounts", bundle: bundle), "Nenhuma conta")
    }
}
