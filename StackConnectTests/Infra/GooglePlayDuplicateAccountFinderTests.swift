import XCTest
@testable import StackConnect

final class GooglePlayDuplicateAccountFinderTests: XCTestCase {

    private var keychain: MockKeyStorable!

    override func setUp() {
        super.setUp()
        keychain = MockKeyStorable()
    }

    override func tearDown() {
        keychain = nil
        super.tearDown()
    }

    private func makeAccount(_ providerType: ProviderType = .googlePlay, json: String?) -> AccountModel {
        let account = AccountModel(name: "Account", providerType: providerType)
        if let json {
            keychain.setObject(GooglePlayCredentials(serviceAccountJSON: json), forKey: "credentials.\(account.id)")
        }
        return account
    }

    // MARK: - identity

    func testIdentityIsTheLowerCasedClientEmail() {
        let json = GooglePlayTestFixtures.serviceAccountJSON(clientEmail: "Stack-Connect@My-Project.iam.gserviceaccount.com")

        XCTAssertEqual(
            GooglePlayDuplicateAccountFinder.identity(of: json),
            "stack-connect@my-project.iam.gserviceaccount.com"
        )
    }

    func testIdentityOfAnUnparseableKeyIsNil() {
        XCTAssertNil(GooglePlayDuplicateAccountFinder.identity(of: "not json"))
        XCTAssertNil(GooglePlayDuplicateAccountFinder.identity(of: GooglePlayTestFixtures.serviceAccountJSON(clientEmail: nil)))
    }

    // MARK: - existingAccount

    func testFindsTheSameServiceAccountRegardlessOfFormattingAndCase() {
        let compact = #"{"type":"service_account","client_email":"STACK-CONNECT@my-project.iam.gserviceaccount.com","private_key_id":"old","private_key":"-----BEGIN PRIVATE KEY-----\nA\n-----END PRIVATE KEY-----\n"}"#
        let existing = makeAccount(json: compact)
        let other = makeAccount(json: GooglePlayTestFixtures.serviceAccountJSON(clientEmail: "other@p.iam.gserviceaccount.com"))

        let match = GooglePlayDuplicateAccountFinder.existingAccount(
            matching: GooglePlayTestFixtures.serviceAccountJSON(privateKeyId: "new"),
            in: [other, existing],
            keychain: keychain
        )

        XCTAssertEqual(match?.id, existing.id)
    }

    func testNoMatchForADifferentServiceAccount() {
        let existing = makeAccount(json: GooglePlayTestFixtures.serviceAccountJSON(clientEmail: "other@p.iam.gserviceaccount.com"))

        XCTAssertNil(GooglePlayDuplicateAccountFinder.existingAccount(
            matching: GooglePlayTestFixtures.serviceAccountJSON(),
            in: [existing],
            keychain: keychain
        ))
    }

    func testAnUnparseableNewKeyIsNeverADuplicate() {
        let existing = makeAccount(json: "{ broken")

        XCTAssertNil(GooglePlayDuplicateAccountFinder.existingAccount(
            matching: "{ broken",
            in: [existing],
            keychain: keychain
        ))
    }

    func testIgnoresOtherProvidersAndAccountsWithoutCredentials() {
        let json = GooglePlayTestFixtures.serviceAccountJSON()
        let firebase = makeAccount(.firebase, json: json)
        let withoutCredentials = makeAccount(json: nil)

        XCTAssertNil(GooglePlayDuplicateAccountFinder.existingAccount(
            matching: json,
            in: [firebase, withoutCredentials],
            keychain: keychain
        ))
    }
}
