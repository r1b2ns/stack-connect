import XCTest
@testable import StackConnect

final class PhasedReleaseScheduleTests: XCTestCase {

    func testPercentagePerDayFollowsApplesSchedule() {
        XCTAssertEqual((1...7).map(PhasedReleaseSchedule.percentage(forDay:)), [1, 2, 5, 10, 20, 50, 100])
    }

    func testOutOfRangeDaysCountAsFullRollout() {
        XCTAssertEqual(PhasedReleaseSchedule.percentage(forDay: 0), 100)
        XCTAssertEqual(PhasedReleaseSchedule.percentage(forDay: 9), 100)
    }

    func testActiveRolloutMarksPreviousDaysDoneAndHighlightsToday() {
        let steps = PhasedReleaseSchedule.steps(for: PhasedReleaseModel(id: "p", state: .active, currentDayNumber: 3))

        XCTAssertEqual(steps.count, 7)
        XCTAssertEqual(steps.map(\.progress), [.done, .done, .current, .upcoming, .upcoming, .upcoming, .upcoming])
        XCTAssertEqual(steps[2].percentage, 5)
    }

    func testPausedRolloutStillHighlightsItsDay() {
        let steps = PhasedReleaseSchedule.steps(for: PhasedReleaseModel(id: "p", state: .paused, currentDayNumber: 1))
        XCTAssertEqual(steps.first?.progress, .current)
        XCTAssertTrue(steps.dropFirst().allSatisfy { $0.progress == .upcoming })
    }

    func testCompleteRolloutHasEveryDayDone() {
        let steps = PhasedReleaseSchedule.steps(for: PhasedReleaseModel(id: "p", state: .complete))
        XCTAssertTrue(steps.allSatisfy { $0.progress == .done })
    }

    func testInactiveOrMissingRolloutIsAllUpcoming() {
        XCTAssertTrue(PhasedReleaseSchedule.steps(for: nil).allSatisfy { $0.progress == .upcoming })
        XCTAssertTrue(PhasedReleaseSchedule.steps(for: PhasedReleaseModel(id: "p", state: .inactive, currentDayNumber: 2))
            .allSatisfy { $0.progress == .upcoming })
    }

    func testOutOfRangeCurrentDayIsClamped() {
        let steps = PhasedReleaseSchedule.steps(for: PhasedReleaseModel(id: "p", state: .active, currentDayNumber: 12))
        XCTAssertEqual(steps.last?.progress, .current)
    }
}

final class VersionDetailPrimaryActionTests: XCTestCase {

    private func actions(
        _ state: AppStoreState?,
        phased: PhasedReleaseStatus? = nil,
        canEdit: Bool = true,
        canDelete: Bool = true
    ) -> [VersionDetailPrimaryAction] {
        VersionDetailPrimaryAction.actions(state: state, phasedState: phased, canEdit: canEdit, canDelete: canDelete)
    }

    func testPrepareForSubmissionOffersSubmit() {
        XCTAssertEqual(actions(.prepareForSubmission), [.submitForReview])
        XCTAssertEqual(actions(.developerRejected), [.submitForReview])
        XCTAssertEqual(actions(.prepareForSubmission, canEdit: false), [])
    }

    func testPendingDeveloperReleaseOffersRejectAndReleaseByPermission() {
        XCTAssertEqual(actions(.pendingDeveloperRelease), [.reject, .release])
        XCTAssertEqual(actions(.pendingDeveloperRelease, canDelete: false), [.release])
        XCTAssertEqual(actions(.pendingDeveloperRelease, canEdit: false), [.reject])
    }

    func testReviewStatesOfferCancel() {
        XCTAssertEqual(actions(.inReview), [.cancelReview])
        XCTAssertEqual(actions(.waitingForReview), [.cancelReview])
        XCTAssertEqual(actions(.readyForReview), [.cancelSubmission])
    }

    func testPhasedReleaseOffersPauseOrResumeAndReleaseToAll() {
        XCTAssertEqual(actions(.readyForSale, phased: .active), [.pausePhasedRelease, .completePhasedRelease])
        XCTAssertEqual(actions(.readyForSale, phased: .paused), [.resumePhasedRelease, .completePhasedRelease])
        XCTAssertEqual(actions(.readyForSale, phased: .complete), [])
        XCTAssertEqual(actions(.readyForSale), [])
        XCTAssertEqual(actions(.readyForSale, phased: .active, canEdit: false), [])
    }

    func testOtherStatesOfferNothing() {
        XCTAssertEqual(actions(.rejected), [])
        XCTAssertEqual(actions(nil), [])
    }

    func testProminenceAndDestructiveRoles() {
        XCTAssertTrue(VersionDetailPrimaryAction.submitForReview.isProminent)
        XCTAssertTrue(VersionDetailPrimaryAction.completePhasedRelease.isProminent)
        XCTAssertFalse(VersionDetailPrimaryAction.pausePhasedRelease.isProminent)
        XCTAssertTrue(VersionDetailPrimaryAction.reject.isDestructive)
        XCTAssertFalse(VersionDetailPrimaryAction.release.isDestructive)
    }
}
