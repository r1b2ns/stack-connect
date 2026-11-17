import Combine
import XCTest
@testable import StackConnect

@MainActor
final class TipJarPromptServiceTests: XCTestCase {

    private let suiteName = "TipJarPromptServiceTests.\(UUID().uuidString)"
    private lazy var defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeService(isEnabled: Bool = true, isForced: Bool = false) -> TipJarPromptService {
        TipJarPromptService(defaults: defaults, isEnabled: isEnabled, isForced: isForced)
    }

    /// The pure rule with every input eligible unless overridden.
    private func shouldShow(
        launchCount: Int = 10,
        syncSucceeded: Bool = true,
        reviewRequestedThisLaunch: Bool = false,
        hasRetiredCard: Bool = false,
        hasTipped: Bool = false,
        isForced: Bool = false
    ) -> Bool {
        TipJarPromptService.shouldShowCard(
            launchCount: launchCount,
            syncSucceeded: syncSucceeded,
            reviewRequestedThisLaunch: reviewRequestedThisLaunch,
            hasRetiredCard: hasRetiredCard,
            hasTipped: hasTipped,
            isForced: isForced
        )
    }

    // MARK: - Pure rule

    func testAllRulesMetShowsTheCard() {
        XCTAssertTrue(shouldShow())
    }

    func testLaunch9DoesNotShow() {
        XCTAssertFalse(shouldShow(launchCount: 9))
    }

    func testLaunch10Shows() {
        XCTAssertTrue(shouldShow(launchCount: 10))
    }

    func testLaterLaunchesShow() {
        XCTAssertTrue(shouldShow(launchCount: 11))
        XCTAssertTrue(shouldShow(launchCount: 37))
    }

    func testPureRuleAcrossLaunchCounts() {
        let eligible = (0...12).filter { shouldShow(launchCount: $0) }
        XCTAssertEqual(eligible, [10, 11, 12])
    }

    func testFailedSyncDoesNotShow() {
        XCTAssertFalse(shouldShow(syncSucceeded: false))
    }

    func testReviewRequestedThisLaunchBlocks() {
        XCTAssertFalse(shouldShow(reviewRequestedThisLaunch: true))
    }

    func testRetiredCardBlocks() {
        XCTAssertFalse(shouldShow(hasRetiredCard: true))
    }

    func testTippedBlocks() {
        XCTAssertFalse(shouldShow(hasTipped: true))
    }

    func testForceIgnoresEveryOtherRule() {
        XCTAssertTrue(shouldShow(
            launchCount: 0,
            syncSucceeded: false,
            reviewRequestedThisLaunch: true,
            hasRetiredCard: true,
            hasTipped: true,
            isForced: true
        ))
    }

    // MARK: - Force argument

    func testForceArgumentParsing() {
        XCTAssertTrue(TipJarPromptService.isForced(arguments: ["app", "-TipJarCardForce", "YES"]))
        XCTAssertTrue(TipJarPromptService.isForced(arguments: ["app", "-TipJarCardForce", "true"]))
        XCTAssertTrue(TipJarPromptService.isForced(arguments: ["app", "-TipJarCardForce", "1"]))
        XCTAssertFalse(TipJarPromptService.isForced(arguments: ["app", "-TipJarCardForce", "NO"]))
        XCTAssertFalse(TipJarPromptService.isForced(arguments: ["app", "-TipJarCardForce"]))
        XCTAssertFalse(TipJarPromptService.isForced(arguments: ["app"]))
        XCTAssertFalse(TipJarPromptService.isForced(arguments: ["app", "-TipJarCardForce", "YES", "-TipJarCardForce", "NO"]))
    }

    // MARK: - Evaluation

    func testHiddenByDefault() {
        XCTAssertFalse(makeService().isCardVisible)
    }

    func testEligibleSyncShowsTheCard() {
        let service = makeService()

        service.evaluateAfterSync(syncSucceeded: true, launchCount: 10, reviewRequestedThisLaunch: false)

        XCTAssertTrue(service.isCardVisible)
    }

    func testIneligibleSyncKeepsItHidden() {
        let service = makeService()

        service.evaluateAfterSync(syncSucceeded: true, launchCount: 9, reviewRequestedThisLaunch: false)

        XCTAssertFalse(service.isCardVisible)
    }

    func testVisibleCardStaysAfterALaterIneligibleSync() {
        let service = makeService()
        service.evaluateAfterSync(syncSucceeded: true, launchCount: 10, reviewRequestedThisLaunch: false)

        service.evaluateAfterSync(syncSucceeded: false, launchCount: 10, reviewRequestedThisLaunch: false)

        XCTAssertTrue(service.isCardVisible)
    }

    func testDisabledServiceNeverShows() {
        let service = makeService(isEnabled: false)

        service.evaluateAfterSync(syncSucceeded: true, launchCount: 10, reviewRequestedThisLaunch: false)

        XCTAssertFalse(service.isCardVisible)
    }

    func testForcedServiceShowsFromTheStartEvenWhenDisabled() {
        let service = makeService(isEnabled: false, isForced: true)
        XCTAssertTrue(service.isCardVisible)
    }

    func testForcedCardStaysHiddenForTheLaunchOnceRetired() {
        let service = makeService(isEnabled: false, isForced: true)
        service.retireCard()

        service.evaluateAfterSync(syncSucceeded: true, launchCount: 10, reviewRequestedThisLaunch: false)

        XCTAssertFalse(service.isCardVisible)
    }

    func testIgnoredCardShowsAgainOnALaterLaunch() {
        let firstLaunch = makeService()
        firstLaunch.evaluateAfterSync(syncSucceeded: true, launchCount: 10, reviewRequestedThisLaunch: false)
        XCTAssertTrue(firstLaunch.isCardVisible)

        let nextLaunch = makeService()
        nextLaunch.evaluateAfterSync(syncSucceeded: true, launchCount: 11, reviewRequestedThisLaunch: false)

        XCTAssertTrue(nextLaunch.isCardVisible)
    }

    func testPublisherEmitsVisibilityChanges() {
        let service = makeService()
        var received: [Bool] = []
        let cancellable = service.isCardVisiblePublisher.sink { received.append($0) }

        service.evaluateAfterSync(syncSucceeded: true, launchCount: 10, reviewRequestedThisLaunch: false)
        service.retireCard()

        XCTAssertEqual(received, [false, true, false])
        cancellable.cancel()
    }

    // MARK: - Persisted flags

    func testRetireHidesAndPersists() {
        let service = makeService()
        service.evaluateAfterSync(syncSucceeded: true, launchCount: 10, reviewRequestedThisLaunch: false)

        service.retireCard()

        XCTAssertFalse(service.isCardVisible)
        XCTAssertTrue(defaults.bool(forKey: TipJarPromptService.hasRetiredCardKey))
        XCTAssertTrue(makeService().hasRetiredCard)
    }

    func testRetiredCardNeverShowsOnLaterLaunches() {
        makeService().retireCard()

        let nextLaunch = makeService()
        nextLaunch.evaluateAfterSync(syncSucceeded: true, launchCount: 20, reviewRequestedThisLaunch: false)

        XCTAssertFalse(nextLaunch.isCardVisible)
    }

    func testCompletedTipHidesAndPersists() {
        let service = makeService()
        service.evaluateAfterSync(syncSucceeded: true, launchCount: 10, reviewRequestedThisLaunch: false)

        service.recordCompletedTip()

        XCTAssertFalse(service.isCardVisible)
        XCTAssertTrue(defaults.bool(forKey: TipJarPromptService.hasTippedKey))
        XCTAssertFalse(defaults.bool(forKey: TipJarPromptService.hasRetiredCardKey))
    }

    func testTippedUserNeverSeesTheCard() {
        makeService().recordCompletedTip()

        let nextLaunch = makeService()
        nextLaunch.evaluateAfterSync(syncSucceeded: true, launchCount: 20, reviewRequestedThisLaunch: false)

        XCTAssertFalse(nextLaunch.isCardVisible)
    }

    func testDisabledServicePersistsNothing() {
        let service = makeService(isEnabled: false, isForced: true)

        service.retireCard()
        service.recordCompletedTip()

        XCTAssertNil(defaults.object(forKey: TipJarPromptService.hasRetiredCardKey))
        XCTAssertNil(defaults.object(forKey: TipJarPromptService.hasTippedKey))
    }
}
