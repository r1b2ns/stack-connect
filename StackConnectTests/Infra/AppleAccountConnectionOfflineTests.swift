import XCTest
@testable import StackConnect

/// Verifies the central offline write-guard in `AppleAccountConnection`:
/// mutating calls fail fast with `OfflineError.noConnection` when the injected
/// `ConnectivityProviding` reports offline, while read/fetch calls are never
/// gated by connectivity.
final class AppleAccountConnectionOfflineTests: XCTestCase {

    private func makeCredentials() -> AppleCredentials {
        AppleCredentials(
            issuerID: "issuer-test",
            privateKeyID: "key-test",
            privateKey: "not-a-real-key"
        )
    }

    private func makeConnection(online: Bool) -> AppleAccountConnection {
        AppleAccountConnection(
            credentials: makeCredentials(),
            connectivity: MockConnectivityProviding(online: online)
        )
    }

    // MARK: - Mutating methods blocked offline

    func testUpdateAppThrowsOfflineErrorWhenOffline() async {
        let connection = makeConnection(online: false)
        do {
            try await connection.updateApp(id: "app-1")
            XCTFail("Expected updateApp to throw OfflineError when offline")
        } catch OfflineError.noConnection {
            // Expected: guard fires before any network work.
        } catch {
            XCTFail("Expected OfflineError.noConnection, got \(error)")
        }
    }

    func testInviteUserThrowsOfflineErrorWhenOffline() async {
        let connection = makeConnection(online: false)
        do {
            try await connection.inviteUser(
                email: "tester@example.com",
                firstName: "Test",
                lastName: "User",
                roles: ["ADMIN"],
                allAppsVisible: true,
                provisioningAllowed: false
            )
            XCTFail("Expected inviteUser to throw OfflineError when offline")
        } catch OfflineError.noConnection {
            // Expected.
        } catch {
            XCTFail("Expected OfflineError.noConnection, got \(error)")
        }
    }

    // MARK: - Read methods are not gated by connectivity

    func testReadMethodIsNotBlockedByOfflineGuard() async {
        let connection = makeConnection(online: false)
        do {
            _ = try await connection.fetchApps()
            // No throw is also acceptable — the point is it is not offline-gated.
        } catch {
            // A read may still fail (invalid test credentials / no network), but it
            // must never be the offline write-guard.
            XCTAssertFalse(
                AppleAPIErrorTranslator.isOffline(error),
                "Read methods must not be gated by the offline write-guard"
            )
        }
    }
}
