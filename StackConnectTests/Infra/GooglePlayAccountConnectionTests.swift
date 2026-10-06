import XCTest
import StackCoreRust
@testable import StackConnect

/// Verifies `GooglePlayAccountConnection`'s offline guard and its Rust-core
/// routing. Every network call is either blocked by the injected offline probe or
/// fails inside `connect(...)` (synchronous, offline), so nothing hits Google.
final class GooglePlayAccountConnectionTests: XCTestCase {

    private typealias Fixtures = GooglePlayTestFixtures

    private func makeConnection(
        json: String = Fixtures.serviceAccountJSON(),
        online: Bool
    ) -> GooglePlayAccountConnection {
        GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(serviceAccountJSON: json),
            connectivity: MockConnectivityProviding(online: online)
        )
    }

    // MARK: - Offline guard

    func testValidateThrowsOfflineErrorWhenOffline() async {
        let connection = makeConnection(online: false)
        do {
            try await connection.validateCredentials()
            XCTFail("Expected validateCredentials to throw OfflineError when offline")
        } catch OfflineError.noConnection {
            // Expected: guard fires before any key parsing or network work.
        } catch {
            XCTFail("Expected OfflineError.noConnection, got \(error)")
        }
    }

    func testFetchAppsThrowsOfflineErrorWhenOffline() async {
        let connection = makeConnection(online: false)
        do {
            _ = try await connection.fetchApps()
            XCTFail("Expected fetchApps to throw OfflineError when offline")
        } catch OfflineError.noConnection {
            // Expected: Play has no offline-capable read, so it fails fast.
        } catch {
            XCTFail("Expected OfflineError.noConnection, got \(error)")
        }
    }

    // MARK: - Rust core routing (online, but no network reached)

    func testValidateWithGarbageKeySurfacesInvalidCredentialsAndFriendlyCopy() async {
        // Well-formed key file whose PEM is not a parseable RSA key: the core
        // rejects it eagerly inside `connect`, before any request.
        let connection = makeConnection(online: true)
        do {
            try await connection.validateCredentials()
            XCTFail("Expected the Rust core to reject the garbage key")
        } catch let error as StackError {
            guard case .InvalidCredentials = error else {
                return XCTFail("Expected StackError.InvalidCredentials, got \(error)")
            }
            XCTAssertEqual(
                GooglePlayErrorTranslator.friendlyMessage(for: error),
                String(localized: "The service account key is invalid. Download a new JSON key from Google Cloud and try again.")
            )
        } catch {
            XCTFail("Expected a StackError, got \(error)")
        }
    }

    func testFetchAppsWithGarbageKeySurfacesInvalidCredentials() async {
        let connection = makeConnection(online: true)
        do {
            _ = try await connection.fetchApps()
            XCTFail("Expected the Rust core to reject the garbage key")
        } catch StackError.InvalidCredentials {
            // Expected.
        } catch {
            XCTFail("Expected StackError.InvalidCredentials, got \(error)")
        }
    }

    func testMalformedStoredJSONSurfacesParseError() async {
        let connection = makeConnection(json: "{ not json", online: true)
        do {
            try await connection.validateCredentials()
            XCTFail("Expected a parse error")
        } catch let error as GooglePlayServiceAccount.ParseError {
            XCTAssertEqual(error, .malformedJSON)
        } catch {
            XCTFail("Expected GooglePlayServiceAccount.ParseError, got \(error)")
        }
    }

    func testDisconnectIsSafeToCallBeforeAndAfterUse() async {
        let connection = makeConnection(online: true)
        connection.disconnect()
        _ = try? await connection.fetchApps()
        connection.disconnect()
    }
}
