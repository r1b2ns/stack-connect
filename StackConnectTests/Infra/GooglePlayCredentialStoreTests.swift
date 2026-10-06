import XCTest
import StackCoreRust
@testable import StackConnect

/// Covers the read-only bridge between the parsed service account and the Rust
/// core's `CredentialStore`, including that the core accepts what it serves.
final class GooglePlayCredentialStoreTests: XCTestCase {

    private typealias Fixtures = GooglePlayTestFixtures

    private func makeStore(json: String = Fixtures.serviceAccountJSON()) throws -> GooglePlayCredentialStore {
        GooglePlayCredentialStore(serviceAccount: try GooglePlayServiceAccount(json: json))
    }

    // MARK: - Schema

    func testKeysMatchRustSchema() {
        // Guards against drift between the app's hard-coded keys and the core's schema.
        let schemaKeys = credentialSchema(kind: .googlePlay).map(\.key)
        XCTAssertEqual(
            schemaKeys,
            [
                GooglePlayCredentialStore.Key.clientEmail,
                GooglePlayCredentialStore.Key.privateKeyId,
                GooglePlayCredentialStore.Key.privateKey
            ]
        )
    }

    // MARK: - Values

    func testMapsCoreKeysToServiceAccountFields() throws {
        let store = try makeStore()

        XCTAssertEqual(store.secret(accountId: "acct", key: GooglePlayCredentialStore.Key.clientEmail), Fixtures.clientEmail)
        XCTAssertEqual(store.secret(accountId: "acct", key: GooglePlayCredentialStore.Key.privateKeyId), Fixtures.privateKeyId)
        XCTAssertEqual(
            store.secret(accountId: "acct", key: GooglePlayCredentialStore.Key.privateKey),
            "-----BEGIN PRIVATE KEY-----\nMIIEfake\n-----END PRIVATE KEY-----\n"
        )
    }

    func testUnknownKeyReturnsNil() throws {
        let store = try makeStore()

        XCTAssertNil(
            store.secret(accountId: "acct", key: "serviceAccountJSON"),
            "Unknown keys must return nil so the core takes its missing-credentials path."
        )
        XCTAssertNil(store.secret(accountId: "acct", key: "projectId"))
    }

    func testWritesAreNoOps() throws {
        let store = try makeStore()

        store.setSecret(accountId: "acct", key: GooglePlayCredentialStore.Key.clientEmail, value: "other@example.com")
        store.delete(accountId: "acct")

        XCTAssertEqual(store.secret(accountId: "acct", key: GooglePlayCredentialStore.Key.clientEmail), Fixtures.clientEmail)
    }

    // MARK: - Rust core

    func testCoreConnectsWithARealKeyFile() throws {
        // A freshly generated PKCS#8 key, JSON-escaped like a downloaded key file.
        let json = Fixtures.serviceAccountJSON(privateKey: try Fixtures.makeRSAPrivateKeyPEM())

        // `connect` is synchronous and offline — no network is touched.
        let provider = try connect(
            kind: .googlePlay,
            accountId: Fixtures.clientEmail,
            store: try makeStore(json: json),
            debugLogger: nil
        )

        XCTAssertEqual(provider.kind(), .googlePlay)
        XCTAssertEqual(provider.capabilities(), [.apps])
    }

    func testCoreRejectsAGarbageKeyWithInvalidCredentials() throws {
        let store = try makeStore()   // "MIIEfake" is not a parseable RSA key

        XCTAssertThrowsError(
            try connect(kind: .googlePlay, accountId: Fixtures.clientEmail, store: store, debugLogger: nil)
        ) { error in
            guard case StackError.InvalidCredentials = error else {
                return XCTFail("Expected StackError.InvalidCredentials, got \(error)")
            }
        }
    }
}
