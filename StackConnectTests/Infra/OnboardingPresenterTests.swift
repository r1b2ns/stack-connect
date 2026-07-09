import XCTest
@testable import StackConnect

final class OnboardingPresenterTests: XCTestCase {

    private func makeSuite() -> (OnboardingPresenter, UserDefaults, String) {
        let suiteName = "OnboardingPresenterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (OnboardingPresenter(defaults: defaults), defaults, suiteName)
    }

    // MARK: - Fresh state

    func testShouldPresentIsTrueForFreshFeature() {
        let (presenter, defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(presenter.shouldPresent(.submissions))
        XCTAssertTrue(presenter.shouldPresent(.analytics))
        XCTAssertFalse(presenter.hasSeen(.submissions))
    }

    // MARK: - After markSeen

    func testMarkSeenFlipsShouldPresentAndHasSeen() {
        let (presenter, defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        presenter.markSeen(.submissions)

        XCTAssertFalse(presenter.shouldPresent(.submissions))
        XCTAssertTrue(presenter.hasSeen(.submissions))
    }

    // MARK: - Independence between features

    func testMarkSeenIsIndependentPerFeature() {
        let (presenter, defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        presenter.markSeen(.submissions)

        // Marking submissions must not affect analytics.
        XCTAssertTrue(presenter.hasSeen(.submissions))
        XCTAssertFalse(presenter.hasSeen(.analytics))
        XCTAssertTrue(presenter.shouldPresent(.analytics))
    }

    // MARK: - Persistence across instances

    func testHasSeenReadsBackFromSharedStore() {
        let (presenter, defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        presenter.markSeen(.analytics)

        // A fresh presenter over the same defaults sees the persisted value.
        let reopened = OnboardingPresenter(defaults: defaults)
        XCTAssertTrue(reopened.hasSeen(.analytics))
        XCTAssertFalse(reopened.shouldPresent(.analytics))
    }

    // MARK: - Key format

    func testKeyFormatMatchesFeatureRawValue() {
        XCTAssertEqual(OnboardingPresenter.key(for: .submissions), "hasSeenOnboarding.submissions")
        XCTAssertEqual(OnboardingPresenter.key(for: .analytics), "hasSeenOnboarding.analytics")
    }
}
