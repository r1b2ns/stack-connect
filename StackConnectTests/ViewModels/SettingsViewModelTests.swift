import XCTest
@testable import StackConnect

@MainActor
final class SettingsViewModelTests: XCTestCase {

    private func makeSUT() -> (SettingsViewModel, AppSettings, UserDefaults, String) {
        let suite = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let appSettings = AppSettings(defaults: defaults)
        let sut = SettingsViewModel(
            storage: MockPersistentStorable(),
            keychain: MockKeyStorable(),
            appSettings: appSettings
        )
        return (sut, appSettings, defaults, suite)
    }

    func testPreReviewChecklistDefaultsToEnabled() {
        let (sut, _, defaults, suite) = makeSUT()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(sut.uiState.preReviewChecklistEnabled)
    }

    func testTogglePersistsToAppSettings() {
        let (sut, appSettings, defaults, suite) = makeSUT()
        defer { defaults.removePersistentDomain(forName: suite) }

        sut.setPreReviewChecklistEnabled(false)

        XCTAssertFalse(sut.uiState.preReviewChecklistEnabled)
        XCTAssertFalse(appSettings.isEnabled(.preReviewChecklistEnabled))
    }
}
