import SwiftUI
import XCTest
@testable import StackConnect

@MainActor
final class AppCommandsTests: XCTestCase {

    func testGoMenuMapsShortcutsToSidebarItems() {
        XCTAssertEqual(RootNavigationShortcut.dashboard.item, .dashboard)
        XCTAssertEqual(RootNavigationShortcut.inReview.item, .releaseQueue(.inReview))
        XCTAssertEqual(RootNavigationShortcut.awaitingRelease.item, .releaseQueue(.awaitingRelease))
        XCTAssertEqual(RootNavigationShortcut.recentReviews.item, .recentReviews)
        XCTAssertEqual(RootNavigationShortcut.settings.item, .settings)
    }

    func testGoMenuKeysAreUnique() {
        let keys = RootNavigationShortcut.allCases.map { String($0.key.character) }
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(keys, ["1", "2", "3", "4", ","])
    }

    func testSelectingFromACommandClearsTheDetail() {
        let coordinator = RootSplitCoordinator()
        coordinator.select(.settings, origin: .sidebar)
        coordinator.contentCoordinator.navigateToLicense()

        coordinator.select(RootNavigationShortcut.recentReviews.item, origin: .menuCommand)

        XCTAssertEqual(coordinator.selection, .recentReviews)
        XCTAssertNil(coordinator.detailRoute)
    }

    func testFindBumpsTheSearchRequest() {
        let coordinator = RootSplitCoordinator()
        XCTAssertEqual(coordinator.searchRequest, 0)

        coordinator.requestSearch()
        coordinator.requestSearch()

        XCTAssertEqual(coordinator.searchRequest, 2)
    }
}
