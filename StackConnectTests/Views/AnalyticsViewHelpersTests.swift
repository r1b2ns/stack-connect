import XCTest
import SwiftUI
import StackProtocols
@testable import StackConnect

/// Covers the side effects behind `.trackScreen(_:)` and `StackTrackedButton`,
/// plus the `EnvironmentValues.analytics` plumbing, through `MockAnalyticsTracker`.
@MainActor
final class AnalyticsViewHelpersTests: XCTestCase {

    func testTrackScreenSendsScreenView() {
        let tracker = MockAnalyticsTracker()

        StackTrackScreenModifier.trackAppear(of: .settings, with: tracker)

        XCTAssertEqual(tracker.trackedEvents, [.screenView(.settings)])
    }

    func testTrackScreenCountsEveryAppearance() {
        let tracker = MockAnalyticsTracker()

        StackTrackScreenModifier.trackAppear(of: .home, with: tracker)
        StackTrackScreenModifier.trackAppear(of: .home, with: tracker)

        XCTAssertEqual(tracker.trackedEvents.count, 2)
    }

    func testTrackedButtonTracksTapThenRunsAction() {
        let tracker = MockAnalyticsTracker()
        var eventsWhenActionRan: [AnalyticsEvent]?

        StackTrackedButton<Text>.performTap(.license, on: .settings, with: tracker) {
            eventsWhenActionRan = tracker.trackedEvents
        }

        XCTAssertEqual(eventsWhenActionRan, [.buttonTap(.license, on: .settings)])
    }

    func testTrackedButtonStillRunsActionWhenAnalyticsDisabled() {
        let tracker = MockAnalyticsTracker(isEnabled: false)
        var ran = false

        StackTrackedButton<Text>.performTap(.license, on: .settings, with: tracker) {
            ran = true
        }

        XCTAssertTrue(ran)
        XCTAssertTrue(tracker.trackedEvents.isEmpty)
    }

    func testEnvironmentDefaultsToSharedService() {
        let values = EnvironmentValues()

        XCTAssertTrue(values.analytics === AnalyticsService.shared)
    }

    func testEnvironmentCanBeOverridden() {
        let tracker = MockAnalyticsTracker()
        var values = EnvironmentValues()

        values.analytics = tracker

        XCTAssertTrue(values.analytics === tracker)
    }
}
