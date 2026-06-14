import XCTest
import StackCoreRust
@testable import StackConnect

/// Covers the first strangler step that routes the Apple connection's
/// `validateCredentials()` / `fetchApps()` through the shared Rust core behind the
/// `useRustCoreForAppleApps` feature flag.
final class RustCoreStranglerTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a `FeatureFlags` backed by an isolated, empty `UserDefaults` suite so
    /// tests never touch the shared store and can assert the OFF/ON states cleanly.
    private func makeFlags(rustCoreOn: Bool) -> FeatureFlags {
        let suiteName = "RustCoreStranglerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let flags = FeatureFlags(defaults: defaults)
        flags.setEnabled(rustCoreOn, for: .useRustCoreForAppleApps)
        return flags
    }

    private let invalidCredentials = AppleCredentials(
        issuerID: "00000000-0000-0000-0000-000000000000",
        privateKeyID: "ABCD1234EF",
        privateKey: "not-a-real-key"
    )

    // MARK: - FeatureFlags

    func testFlagDefaultsOffWhenUnset() {
        let suiteName = "RustCoreStranglerTests.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let flags = FeatureFlags(defaults: defaults)

        XCTAssertFalse(
            flags.isEnabled(.useRustCoreForAppleApps),
            "New flag must default to OFF (safe, reversible)."
        )
    }

    func testFlagCanBeToggled() {
        let flags = makeFlags(rustCoreOn: true)
        XCTAssertTrue(flags.isEnabled(.useRustCoreForAppleApps))

        flags.setEnabled(false, for: .useRustCoreForAppleApps)
        XCTAssertFalse(flags.isEnabled(.useRustCoreForAppleApps))
    }

    // MARK: - AppleCredentialStore bridge

    func testCredentialStoreMapsRustKeysToAppleCredentials() {
        let store = AppleCredentialStore(credentials: invalidCredentials)

        XCTAssertEqual(
            store.secret(accountId: "acct", key: AppleCredentialStore.Key.issuerId),
            invalidCredentials.issuerID
        )
        XCTAssertEqual(
            store.secret(accountId: "acct", key: AppleCredentialStore.Key.keyId),
            invalidCredentials.privateKeyID
        )
        XCTAssertEqual(
            store.secret(accountId: "acct", key: AppleCredentialStore.Key.privateKeyP8),
            invalidCredentials.privateKey
        )
        XCTAssertNil(
            store.secret(accountId: "acct", key: "unknownKey"),
            "Unknown keys must return nil so the core takes its missing-credentials path."
        )
    }

    func testCredentialStoreKeysMatchRustSchema() {
        // Guards against drift between the app's hard-coded keys and the core's schema.
        let schemaKeys = credentialSchema(kind: .appStoreConnect).map(\.key)
        XCTAssertEqual(
            schemaKeys,
            [
                AppleCredentialStore.Key.issuerId,
                AppleCredentialStore.Key.keyId,
                AppleCredentialStore.Key.privateKeyP8
            ]
        )
    }

    // MARK: - Routing (ON path)

    /// With the flag ON, invalid credentials must surface a Rust-core `StackError`.
    /// This proves `validateCredentials()` is going through the Rust `Provider`
    /// (which validates the EC key locally) rather than the Swift SDK path.
    func testValidateRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            try await connection.validateCredentials()
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch let error as StackError {
            // Any StackError confirms the call crossed into the Rust core. The
            // malformed private key surfaces as .invalidCredentials.
            switch error {
            case .InvalidCredentials, .Auth, .Network, .Http, .Decode, .Unsupported:
                break
            }
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `fetchApps()` must also fail via the Rust core for invalid
    /// credentials (it cannot reach the Swift-SDK provider, which is never built).
    func testFetchAppsRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            _ = try await connection.fetchApps()
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `fetchReviewSubmissions(appId:)` must also fail via the Rust
    /// core for invalid credentials, proving it never reaches the Swift-SDK provider.
    func testFetchReviewSubmissionsRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            _ = try await connection.fetchReviewSubmissions(appId: "123456789")
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    // MARK: - Review submission mapping (Rust core -> app model)

    /// The core `ReviewSubmission` must map field-for-field onto the app's
    /// `ReviewSubmissionModel`, including ISO8601 date parsing of `submittedDate`.
    func testMapReviewSubmissionMapsAllFieldsAndParsesDate() {
        let core = StackCoreRust.ReviewSubmission(
            id: "sub-1",
            appId: "123456789",
            platform: "IOS",
            submittedDate: "2024-01-15T10:30:00Z",
            state: "IN_REVIEW",
            versionString: "2.1.0",
            versionId: "ver-1",
            submittedByName: "Jane Doe",
            submittedByEmail: "jane@example.com"
        )

        let model = AppleAccountConnection.mapReviewSubmission(core)

        XCTAssertEqual(model.id, "sub-1")
        XCTAssertEqual(model.appId, "123456789")
        XCTAssertEqual(model.platform, "IOS")
        XCTAssertEqual(model.state, "IN_REVIEW")
        XCTAssertEqual(model.versionString, "2.1.0")
        XCTAssertEqual(model.versionId, "ver-1")
        XCTAssertEqual(model.submittedByName, "Jane Doe")
        XCTAssertEqual(model.submittedByEmail, "jane@example.com")

        let expected = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")
        XCTAssertEqual(model.submittedDate, expected)
    }

    /// App Store Connect timestamps may include fractional seconds; the parser must
    /// tolerate that form too.
    func testMapReviewSubmissionParsesFractionalSecondsDate() {
        let core = StackCoreRust.ReviewSubmission(
            id: "sub-2",
            appId: "123456789",
            platform: nil,
            submittedDate: "2024-01-15T10:30:00.123Z",
            state: nil,
            versionString: nil,
            versionId: nil,
            submittedByName: nil,
            submittedByEmail: nil
        )

        let model = AppleAccountConnection.mapReviewSubmission(core)

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(model.submittedDate, withFractional.date(from: "2024-01-15T10:30:00.123Z"))
    }

    /// A nil or unparseable `submittedDate` must yield a nil `Date?` without crashing.
    func testMapReviewSubmissionHandlesMissingAndInvalidDate() {
        let missing = StackCoreRust.ReviewSubmission(
            id: "sub-3", appId: "1", platform: nil, submittedDate: nil,
            state: nil, versionString: nil, versionId: nil,
            submittedByName: nil, submittedByEmail: nil
        )
        XCTAssertNil(AppleAccountConnection.mapReviewSubmission(missing).submittedDate)

        let invalid = StackCoreRust.ReviewSubmission(
            id: "sub-4", appId: "1", platform: nil, submittedDate: "not-a-date",
            state: nil, versionString: nil, versionId: nil,
            submittedByName: nil, submittedByEmail: nil
        )
        XCTAssertNil(AppleAccountConnection.mapReviewSubmission(invalid).submittedDate)
    }
}
