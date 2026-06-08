import XCTest
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Unit tests for `WindowsAddAccountOptionsModel` (T-F08).
///
/// Covers: the routing decision logic extracted from WindowsAddAccountOptionsView.
/// The model determines which options are shown and what navigation target each
/// maps to, based on the selected `ProviderType`.
///
/// Test coverage:
///   - Apple provider: "Create New" returns `.createAppleAccount`, Import is shown
///   - Firebase provider: "Create New" returns `.createFirebaseAccount`, Import is hidden
///   - Google Play provider: "Create New" returns nil (unsupported), Import is hidden
@MainActor
final class WindowsAddAccountOptionsModelTests: XCTestCase {

    // MARK: - Apple Provider (AC-1, AC-2, AC-3)

    func testAppleProviderShowsImportOption() {
        let sut = WindowsAddAccountOptionsModel(provider: .apple)

        XCTAssertTrue(sut.showImportOption,
                      "Import .scexport should be shown for Apple provider (AC-1)")
    }

    func testAppleProviderCreateRoutePushesCreateAppleAccount() {
        let sut = WindowsAddAccountOptionsModel(provider: .apple)

        XCTAssertEqual(sut.createRoute, .createAppleAccount,
                       "Create New for Apple should push .createAppleAccount (AC-2)")
    }

    func testAppleProviderExposesCorrectProvider() {
        let sut = WindowsAddAccountOptionsModel(provider: .apple)

        XCTAssertEqual(sut.provider, .apple)
    }

    // MARK: - Firebase Provider (AC-1, AC-2)

    func testFirebaseProviderHidesImportOption() {
        let sut = WindowsAddAccountOptionsModel(provider: .firebase)

        XCTAssertFalse(sut.showImportOption,
                       "Import .scexport should NOT be shown for Firebase provider (AC-1)")
    }

    func testFirebaseProviderCreateRoutePushesCreateFirebaseAccount() {
        let sut = WindowsAddAccountOptionsModel(provider: .firebase)

        XCTAssertEqual(sut.createRoute, .createFirebaseAccount,
                       "Create New for Firebase should push .createFirebaseAccount (AC-2)")
    }

    func testFirebaseProviderExposesCorrectProvider() {
        let sut = WindowsAddAccountOptionsModel(provider: .firebase)

        XCTAssertEqual(sut.provider, .firebase)
    }

    // MARK: - Google Play Provider (exhaustiveness guard)

    func testGooglePlayProviderHidesImportOption() {
        let sut = WindowsAddAccountOptionsModel(provider: .googlePlay)

        XCTAssertFalse(sut.showImportOption,
                       "Import .scexport should NOT be shown for Google Play provider")
    }

    func testGooglePlayProviderCreateRouteReturnsNil() {
        let sut = WindowsAddAccountOptionsModel(provider: .googlePlay)

        XCTAssertNil(sut.createRoute,
                     "Create New for Google Play should return nil (unsupported flow)")
    }

    // MARK: - All Providers: Import Route is always .importScexport

    func testShowImportOptionIsTrueOnlyForApple() {
        // Verify across all provider types that import is exclusive to Apple.
        for provider in ProviderType.allCases {
            let sut = WindowsAddAccountOptionsModel(provider: provider)
            if provider == .apple {
                XCTAssertTrue(sut.showImportOption,
                              "showImportOption should be true for \(provider)")
            } else {
                XCTAssertFalse(sut.showImportOption,
                               "showImportOption should be false for \(provider)")
            }
        }
    }
}
