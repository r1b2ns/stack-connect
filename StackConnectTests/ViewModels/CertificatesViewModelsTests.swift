import XCTest
import StackProtocols
@testable import StackConnect

/// Analytics coverage for the certificate list / detail / create ViewModels.
/// Network paths build their `AppleAccountConnection` inline, so only the
/// no-credentials and local (CSR file, validation) paths run offline.
@MainActor
final class CertificatesViewModelsTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private let account = AccountModel(name: "Team", providerType: .apple)
    private let certificate = CertificateModel(
        id: "cert-1",
        displayName: "Apple Distribution",
        name: "Apple Distribution: Team",
        certificateType: "DISTRIBUTION",
        platform: nil,
        serialNumber: nil,
        expirationDate: nil,
        isActivated: true
    )

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - CertificatesList

    func testListLoadTracksNothingAndRefreshTracksFailure() async {
        let sut = CertificatesListViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .certificatesList, result: .failure)])
    }

    // MARK: - CertificateDetail

    func testDetailDownloadAndRevokeTrackTapAndFailureWithoutCredentials() async {
        let sut = CertificateDetailViewModel(account: account, certificate: certificate, keychain: MockKeyStorable(), analytics: analytics)

        let url = await sut.prepareDownload()
        let revoked = await sut.revoke()

        XCTAssertNil(url)
        XCTAssertFalse(revoked)
        XCTAssertEqual(analytics.taps(of: .download), [.buttonTap(.download, on: .certificateDetail)])
        XCTAssertEqual(analytics.taps(of: .confirmRevoke), [.buttonTap(.confirmRevoke, on: .certificateDetail)])
        XCTAssertEqual(analytics.actions(of: .downloadCertificate), [.action(.downloadCertificate, on: .certificateDetail, result: .failure)])
        XCTAssertEqual(analytics.actions(of: .revokeCertificate), [.action(.revokeCertificate, on: .certificateDetail, result: .failure)])
    }

    // MARK: - CreateCertificate

    func testLoadCSRTracksSuccessAndFailure() async throws {
        let sut = CreateCertificateViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("analytics-test-\(UUID().uuidString).csr")
        try "-----BEGIN CERTIFICATE REQUEST-----\nQUJD\n-----END CERTIFICATE REQUEST-----".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        await sut.loadCSR(from: url)
        await sut.loadCSR(from: url.appendingPathExtension("missing"))

        XCTAssertEqual(analytics.results(of: .importCsr), [.success, .failure])
    }

    func testSubmitWithoutCSRTracksOnlyTheTap() async {
        let sut = CreateCertificateViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)

        await sut.submit()

        XCTAssertEqual(analytics.taps(of: .create), [.buttonTap(.create, on: .createCertificate)])
        XCTAssertTrue(analytics.actions(of: .createCertificate).isEmpty)
    }

    func testSubmitTracksFailureWithCertificateTypeOnly() async {
        let sut = CreateCertificateViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)
        sut.selectType(.iosDistribution)
        sut.uiState.csrContent = "QUJD"

        await sut.submit()

        XCTAssertEqual(analytics.actions(of: .createCertificate), [
            .action(.createCertificate, on: .createCertificate, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string("IOS_DISTRIBUTION")
            ])
        ])
    }

    func testPrepareDownloadTracksTapAndFailureWhenNothingWasCreated() {
        let sut = CreateCertificateViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)

        XCTAssertNil(sut.prepareDownload())

        XCTAssertEqual(analytics.taps(of: .download), [.buttonTap(.download, on: .createCertificate)])
        XCTAssertEqual(analytics.results(of: .downloadCertificate), [.failure])
    }

    func testPrepareDownloadTracksSuccessForCreatedCertificate() {
        let sut = CreateCertificateViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)
        sut.uiState.createdCertificate = certificate
        sut.uiState.createdContentBase64 = Data("cert".utf8).base64EncodedString()

        let url = sut.prepareDownload()
        if let url { try? FileManager.default.removeItem(at: url) }

        XCTAssertNotNil(url)
        XCTAssertEqual(analytics.results(of: .downloadCertificate), [.success])
    }
}
