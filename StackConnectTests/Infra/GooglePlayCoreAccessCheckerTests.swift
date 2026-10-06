import XCTest
import StackCoreRust
@testable import StackConnect

/// The manual "add app by package name" check now runs on the Rust core's
/// `fetchAppDetails` (APIProviderPlay removed): success = reachable, HTTP 404 =
/// unknown package, `.Auth` = no access.
final class GooglePlayCoreAccessCheckerTests: XCTestCase {

    func testReachableAppPassesAndAsksForThatPackage() async throws {
        let connection = MockGooglePlayAccountConnection()
        let checker = GooglePlayCoreAccessChecker(appDetails: connection)

        try await checker.verifyAccess(packageName: "com.example.app")

        XCTAssertEqual(connection.appDetailsRequests, ["com.example.app"])
    }

    func testUnknownPackageSurfacesNotFoundWithPackageCopy() async {
        let connection = MockGooglePlayAccountConnection()
        connection.fetchAppDetailsHandler = { name in
            throw StackError.Http(status: 404, message: "Google Play found no app with package name \(name)")
        }
        let checker = GooglePlayCoreAccessChecker(appDetails: connection)

        do {
            try await checker.verifyAccess(packageName: "com.nope")
            XCTFail("Expected the 404 to propagate")
        } catch {
            guard case StackError.Http(404, _) = error else {
                return XCTFail("Expected StackError.Http(404), got \(error)")
            }
            XCTAssertEqual(
                GooglePlayErrorTranslator.friendlyMessage(for: error),
                String(localized: "Google Play found no app with this package name. Check it in Play Console and try again.")
            )
        }
    }

    func testNoAccessSurfacesAuthWithTheCoresDetail() async {
        let detail = "The service account has no access to com.example.app."
        let connection = MockGooglePlayAccountConnection()
        connection.fetchAppDetailsHandler = { _ in throw StackError.Auth(message: detail) }
        let checker = GooglePlayCoreAccessChecker(appDetails: connection)

        do {
            try await checker.verifyAccess(packageName: "com.example.app")
            XCTFail("Expected the auth error to propagate")
        } catch {
            guard case StackError.Auth = error else {
                return XCTFail("Expected StackError.Auth, got \(error)")
            }
            XCTAssertEqual(
                GooglePlayErrorTranslator.friendlyMessage(for: error),
                String(localized: "Google Play denied access to this service account.") + "\n" + detail
            )
        }
    }

    /// End to end through the app list: the default checker is the core one, so a
    /// 404 from `fetchAppDetails` lands in the add sheet as "package not found".
    @MainActor
    func testAppListManualAddShowsNotFoundFromTheCoreCheck() async {
        let account = AccountModel(name: "Play Team", providerType: .googlePlay)
        let keychain = MockKeyStorable()
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )
        let connection = MockGooglePlayAccountConnection()
        connection.fetchAppDetailsHandler = { _ in throw StackError.Http(status: 404, message: "not found") }
        let sut = GooglePlayAppListViewModel(
            account: account,
            keychain: keychain,
            storage: MockPersistentStorable(),
            connectionFactory: connection.factory,
            accessCheckerFactory: { GooglePlayCoreAccessChecker(appDetails: connection.appDetailsFactory($0)) }
        )

        await sut.addApp(packageName: "com.nope")

        XCTAssertEqual(
            sut.uiState.addError,
            String(localized: "Google Play found no app with this package name. Check it in Play Console and try again.")
        )
        XCTAssertTrue(sut.uiState.apps.isEmpty)
        XCTAssertEqual(connection.appDetailsRequests, ["com.nope"])
    }
}
