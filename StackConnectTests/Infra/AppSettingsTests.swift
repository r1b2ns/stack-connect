import XCTest
@testable import StackConnect

final class AppSettingsTests: XCTestCase {

    private func makeSuite() -> (AppSettings, UserDefaults, String) {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (AppSettings(defaults: defaults), defaults, suiteName)
    }

    func testPreReviewChecklistDefaultsToEnabled() {
        let (settings, defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(settings.isEnabled(.preReviewChecklistEnabled))
    }

    func testSetEnabledPersists() {
        let (settings, defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setEnabled(false, for: .preReviewChecklistEnabled)
        XCTAssertFalse(settings.isEnabled(.preReviewChecklistEnabled))

        settings.setEnabled(true, for: .preReviewChecklistEnabled)
        XCTAssertTrue(settings.isEnabled(.preReviewChecklistEnabled))
    }

    func testValueReadsBackFromSharedStore() {
        let (settings, defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.setEnabled(false, for: .preReviewChecklistEnabled)

        // A fresh instance over the same defaults sees the persisted value.
        let reopened = AppSettings(defaults: defaults)
        XCTAssertFalse(reopened.isEnabled(.preReviewChecklistEnabled))
    }
}
