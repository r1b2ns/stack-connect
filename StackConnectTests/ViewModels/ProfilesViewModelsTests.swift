import XCTest
import StackProtocols
@testable import StackConnect

/// Analytics coverage for the provisioning profile list / detail / create ViewModels.
@MainActor
final class ProfilesViewModelsTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private let account = AccountModel(name: "Team", providerType: .apple)
    private let profile = ProvisioningProfileModel(
        id: "profile-1",
        name: "Example AppStore",
        profileType: "IOS_APP_STORE",
        profileState: "ACTIVE",
        platform: "IOS",
        uuid: nil,
        bundleId: nil,
        createdDate: nil,
        expirationDate: nil
    )

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - ProfilesList

    func testListLoadTracksNothingAndRefreshTracksFailure() async {
        let sut = ProfilesListViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .profilesList, result: .failure)])
    }

    // MARK: - ProfileDetail

    func testDetailDownloadAndDeleteTrackTapAndFailureWithoutCredentials() async {
        let sut = ProfileDetailViewModel(account: account, profile: profile, keychain: MockKeyStorable(), analytics: analytics)

        _ = await sut.prepareDownload()
        _ = await sut.delete()

        XCTAssertEqual(analytics.taps(of: .download), [.buttonTap(.download, on: .profileDetail)])
        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .profileDetail)])
        XCTAssertEqual(analytics.actions(of: .downloadProfile), [.action(.downloadProfile, on: .profileDetail, result: .failure)])
        XCTAssertEqual(analytics.actions(of: .deleteProfile), [.action(.deleteProfile, on: .profileDetail, result: .failure)])
    }

    // MARK: - CreateProfile

    func testSubmitWithMissingFieldsTracksOnlyTheTap() async {
        let sut = CreateProfileViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)

        await sut.submit()

        XCTAssertEqual(analytics.taps(of: .create), [.buttonTap(.create, on: .createProfile)])
        XCTAssertTrue(analytics.actions(of: .createProfile).isEmpty)
    }

    func testSubmitTracksFailureWithProfileTypeOnly() async throws {
        let sut = CreateProfileViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)
        let type = try XCTUnwrap(ProfileTypeCatalog.all.first { $0.raw == "IOS_APP_STORE" })
        sut.selectType(type)
        sut.selectBundleId(BundleIdentifierModel(id: "b-1", identifier: "com.example.app", name: "Example", platform: "IOS", seedId: nil))
        sut.toggleCertificate(id: "cert-1")
        sut.uiState.name = "Secret profile name"

        await sut.submit()

        XCTAssertEqual(analytics.actions(of: .createProfile), [
            .action(.createProfile, on: .createProfile, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string("IOS_APP_STORE")
            ])
        ])
    }

    func testPrepareDownloadTracksTapAndOutcome() {
        let sut = CreateProfileViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)

        XCTAssertNil(sut.prepareDownload())
        sut.uiState.createdProfile = profile
        sut.uiState.createdContentBase64 = Data("profile".utf8).base64EncodedString()
        let url = sut.prepareDownload()
        if let url { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(analytics.taps(of: .download).count, 2)
        XCTAssertEqual(analytics.results(of: .downloadProfile), [.failure, .success])
    }
}
