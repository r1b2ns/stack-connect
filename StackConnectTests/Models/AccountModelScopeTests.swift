import XCTest
@testable import StackConnect

final class AccountModelScopeTests: XCTestCase {

    // MARK: - allowsApp truth table

    func testNilScopeAllowsEveryApp() {
        let account = AccountModel(name: "A", providerType: .apple, appsBundles: nil)
        XCTAssertTrue(account.allowsApp(bundleId: "com.a"))
        XCTAssertTrue(account.allowsApp(bundleId: "com.b"))
    }

    func testEmptyScopeAllowsEveryApp() {
        let account = AccountModel(name: "A", providerType: .apple, appsBundles: [])
        XCTAssertTrue(account.allowsApp(bundleId: "com.a"))
        XCTAssertTrue(account.allowsApp(bundleId: "anything"))
    }

    func testNonEmptyScopeAllowsOnlyListedBundles() {
        let account = AccountModel(name: "A", providerType: .apple, appsBundles: ["com.a"])
        XCTAssertTrue(account.allowsApp(bundleId: "com.a"))
        XCTAssertFalse(account.allowsApp(bundleId: "com.b"))
    }

    // MARK: - Codable round-trips

    func testCodableRoundTripPreservesScope() throws {
        let account = AccountModel(name: "A", providerType: .apple, appsBundles: ["com.a", "com.b"])
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(AccountModel.self, from: data)
        XCTAssertEqual(decoded.appsBundles, ["com.a", "com.b"])
    }

    /// Legacy JSON without the key must decode to nil ⇒ no restriction.
    func testLegacyJSONWithoutKeyDecodesToNil() throws {
        let json = """
        {
            "id": "123",
            "name": "Legacy",
            "providerType": "apple",
            "createdAt": 700000000,
            "rules": {},
            "origin": "created",
            "role": "unspecified",
            "hasPendingAgreements": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AccountModel.self, from: data)
        XCTAssertNil(decoded.appsBundles)
        XCTAssertTrue(decoded.allowsApp(bundleId: "anything"))
    }
}
