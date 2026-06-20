import XCTest
import StackCoreRust
@testable import StackConnect

/// Verifies the pending Program License Agreement detection seam on the four
/// App Store Connect resource list ViewModels (Certificates, Identifiers,
/// Devices, Profiles). Each `load()` builds its `AppleAccountConnection` inline,
/// so the catch logic is exercised through the injectable `handleLoadError(_:)`
/// seam rather than the full async `load()`.
///
/// For each ViewModel we assert two paths:
/// - A `StackError.PendingAgreements` flips `pendingAgreement` to `true` and
///   leaves `errorMessage` nil (friendly tip, not a hard error).
/// - Any other error leaves `pendingAgreement` false and surfaces the error's
///   `localizedDescription` as `errorMessage` (the pre-existing behaviour).

@MainActor
final class ProvisioningListsPendingAgreementTests: XCTestCase {

    // MARK: - Helpers

    private func makeAccount() -> AccountModel {
        AccountModel(name: "Test Account", providerType: .apple)
    }

    private var pendingAgreementError: Error {
        StackCoreRust.StackError.PendingAgreements(message: "Pending Program License Agreement")
    }

    private var genericError: Error {
        NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
    }

    // MARK: - Certificates

    func testCertificatesPendingAgreementSetsFlagOnly() {
        let sut = CertificatesListViewModel(account: makeAccount(), keychain: MockKeyStorable())

        sut.handleLoadError(pendingAgreementError)

        XCTAssertTrue(sut.uiState.pendingAgreement)
        XCTAssertNil(sut.uiState.errorMessage)
    }

    func testCertificatesGenericErrorSetsMessageNotFlag() {
        let sut = CertificatesListViewModel(account: makeAccount(), keychain: MockKeyStorable())

        sut.handleLoadError(genericError)

        XCTAssertFalse(sut.uiState.pendingAgreement)
        XCTAssertEqual(sut.uiState.errorMessage, genericError.localizedDescription)
    }

    // MARK: - Identifiers

    func testIdentifiersPendingAgreementSetsFlagOnly() {
        let sut = IdentifiersListViewModel(account: makeAccount(), keychain: MockKeyStorable())

        sut.handleLoadError(pendingAgreementError)

        XCTAssertTrue(sut.uiState.pendingAgreement)
        XCTAssertNil(sut.uiState.errorMessage)
    }

    func testIdentifiersGenericErrorSetsMessageNotFlag() {
        let sut = IdentifiersListViewModel(account: makeAccount(), keychain: MockKeyStorable())

        sut.handleLoadError(genericError)

        XCTAssertFalse(sut.uiState.pendingAgreement)
        XCTAssertEqual(sut.uiState.errorMessage, genericError.localizedDescription)
    }

    // MARK: - Devices

    func testDevicesPendingAgreementSetsFlagOnly() {
        let sut = DevicesListViewModel(account: makeAccount(), keychain: MockKeyStorable())

        sut.handleLoadError(pendingAgreementError)

        XCTAssertTrue(sut.uiState.pendingAgreement)
        XCTAssertNil(sut.uiState.errorMessage)
    }

    func testDevicesGenericErrorSetsMessageNotFlag() {
        let sut = DevicesListViewModel(account: makeAccount(), keychain: MockKeyStorable())

        sut.handleLoadError(genericError)

        XCTAssertFalse(sut.uiState.pendingAgreement)
        XCTAssertEqual(sut.uiState.errorMessage, genericError.localizedDescription)
    }

    // MARK: - Profiles

    func testProfilesPendingAgreementSetsFlagOnly() {
        let sut = ProfilesListViewModel(account: makeAccount(), keychain: MockKeyStorable())

        sut.handleLoadError(pendingAgreementError)

        XCTAssertTrue(sut.uiState.pendingAgreement)
        XCTAssertNil(sut.uiState.errorMessage)
    }

    func testProfilesGenericErrorSetsMessageNotFlag() {
        let sut = ProfilesListViewModel(account: makeAccount(), keychain: MockKeyStorable())

        sut.handleLoadError(genericError)

        XCTAssertFalse(sut.uiState.pendingAgreement)
        XCTAssertEqual(sut.uiState.errorMessage, genericError.localizedDescription)
    }
}
