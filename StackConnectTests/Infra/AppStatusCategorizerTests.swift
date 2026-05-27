import XCTest
@testable import StackConnect

final class AppStatusCategorizerTests: XCTestCase {

    func testCategorizeGroupsReviewStates() {
        let apps: [AppModel] = [
            makeApp(id: "1", state: .waitingForReview),
            makeApp(id: "2", state: .inReview),
            makeApp(id: "3", state: .rejected),
            makeApp(id: "4", state: .readyForSale)
        ]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: [:])

        XCTAssertEqual(Set(result.inReview.map(\.id)), ["1", "2", "3"])
        XCTAssertTrue(result.awaitingRelease.isEmpty)
    }

    func testPendingDeveloperReleaseIsAwaitingRelease() {
        let apps = [makeApp(id: "1", state: .pendingDeveloperRelease)]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: [:])

        XCTAssertEqual(result.awaitingRelease.map(\.id), ["1"])
        XCTAssertTrue(result.inReview.isEmpty)
    }

    func testReadyForSaleWithActivePhasedIsAwaitingRelease() {
        let apps = [makeApp(id: "1", state: .readyForSale)]
        let phased = ["1": PhasedReleaseModel(id: "phased.1", state: .active)]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: phased)

        XCTAssertEqual(result.awaitingRelease.map(\.id), ["1"])
    }

    func testReadyForSaleWithPausedPhasedIsAwaitingRelease() {
        let apps = [makeApp(id: "1", state: .readyForSale)]
        let phased = ["1": PhasedReleaseModel(id: "phased.1", state: .paused)]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: phased)

        XCTAssertEqual(result.awaitingRelease.map(\.id), ["1"])
    }

    func testReadyForSaleWithCompletePhasedIsIgnored() {
        let apps = [makeApp(id: "1", state: .readyForSale)]
        let phased = ["1": PhasedReleaseModel(id: "phased.1", state: .complete)]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: phased)

        XCTAssertTrue(result.awaitingRelease.isEmpty)
        XCTAssertTrue(result.inReview.isEmpty)
    }

    func testAppsWithoutStateAreIgnored() {
        let apps = [makeApp(id: "1", state: nil)]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: [:])

        XCTAssertTrue(result.inReview.isEmpty)
        XCTAssertTrue(result.awaitingRelease.isEmpty)
    }

    // MARK: - Helpers

    private func makeApp(id: String, state: AppStoreState?) -> AppModel {
        AppModel(
            id: id,
            name: "App \(id)",
            bundleId: "com.test.\(id)",
            accountId: "acc",
            appStoreState: state
        )
    }
}
