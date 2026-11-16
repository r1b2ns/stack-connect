import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AppAccessibilityViewModelTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private var sut: AppAccessibilityViewModel!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
        sut = AppAccessibilityViewModel(
            appId: "app-1",
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )
    }

    override func tearDown() async throws {
        sut = nil
        analytics = nil
        try await super.tearDown()
    }

    private let declaration = AccessibilityDeclarationModel(
        id: "decl-1",
        deviceFamily: "IPHONE",
        state: "DRAFT",
        supportsAudioDescriptions: false,
        supportsCaptions: false,
        supportsDarkInterface: true,
        supportsDifferentiateWithoutColor: false,
        supportsLargerText: true,
        supportsReducedMotion: false,
        supportsSufficientContrast: false,
        supportsVoiceControl: false,
        supportsVoiceover: true
    )

    func testRefreshTracksFailureWithoutCredentials() async {
        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .appAccessibility, result: .failure)])
    }

    func testEditActionsTrackTapAndFailureWithoutCredentials() async {
        await sut.save(declaration: declaration)
        await sut.publish(declaration: declaration)
        await sut.delete(declaration: declaration)

        XCTAssertEqual(analytics.taps(of: .save), [.buttonTap(.save, on: .appAccessibilityEdit)])
        XCTAssertEqual(analytics.taps(of: .publish), [.buttonTap(.publish, on: .appAccessibilityEdit)])
        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .appAccessibility)])
        XCTAssertEqual(analytics.results(of: .updateAccessibility), [.failure])
        XCTAssertEqual(analytics.results(of: .publishAccessibility), [.failure])
        XCTAssertEqual(analytics.results(of: .deleteAccessibility), [.failure])
    }

    func testCreateTracksDeviceFamilyOnly() async {
        await sut.create(deviceFamily: "IPAD")

        XCTAssertEqual(analytics.actions(of: .createAccessibility), [
            .action(.createAccessibility, on: .appAccessibilityAddDeviceFamily, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string("IPAD")
            ])
        ])
    }
}
