import XCTest
@testable import StackConnect

@MainActor
final class ReviewPromptServiceTests: XCTestCase {

    private let suiteName = "ReviewPromptServiceTests.\(UUID().uuidString)"
    private lazy var defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    /// A fresh "process" on launch number `launch`: the counter persisted by the
    /// previous launches, then a new service registering this one.
    private func makeService(onLaunch launch: Int, isEnabled: Bool = true) -> ReviewPromptService {
        defaults.set(launch - 1, forKey: ReviewPromptService.launchCountKey)
        let service = ReviewPromptService(defaults: defaults, isEnabled: isEnabled)
        service.registerLaunch()
        return service
    }

    // MARK: - Launch counting

    func testRegisterLaunchIncrementsPersistedCounter() {
        let first = ReviewPromptService(defaults: defaults)
        first.registerLaunch()
        XCTAssertEqual(first.launchCount, 1)

        let second = ReviewPromptService(defaults: defaults)
        second.registerLaunch()
        XCTAssertEqual(second.launchCount, 2)
        XCTAssertEqual(defaults.integer(forKey: ReviewPromptService.launchCountKey), 2)
    }

    func testRegisterLaunchCountsOncePerProcess() {
        let service = ReviewPromptService(defaults: defaults)
        service.registerLaunch()
        service.registerLaunch()
        service.registerLaunch()
        XCTAssertEqual(service.launchCount, 1)
    }

    func testDisabledServiceNeitherCountsNorRequests() {
        let service = makeService(onLaunch: 3, isEnabled: false)
        XCTAssertEqual(service.launchCount, 2)
        XCTAssertFalse(service.shouldRequestReview(syncSucceeded: true))
    }

    func testNoRequestBeforeTheLaunchIsRegistered() {
        defaults.set(3, forKey: ReviewPromptService.launchCountKey)
        let service = ReviewPromptService(defaults: defaults)
        XCTAssertFalse(service.shouldRequestReview(syncSucceeded: true))
    }

    // MARK: - Launch rule

    func testLaunch1DoesNotRequest() {
        XCTAssertFalse(makeService(onLaunch: 1).shouldRequestReview(syncSucceeded: true))
    }

    func testLaunch2DoesNotRequest() {
        XCTAssertFalse(makeService(onLaunch: 2).shouldRequestReview(syncSucceeded: true))
    }

    func testLaunch3Requests() {
        XCTAssertTrue(makeService(onLaunch: 3).shouldRequestReview(syncSucceeded: true))
    }

    func testLaunch4DoesNotRequest() {
        XCTAssertFalse(makeService(onLaunch: 4).shouldRequestReview(syncSucceeded: true))
    }

    func testLaunch6Requests() {
        XCTAssertTrue(makeService(onLaunch: 6).shouldRequestReview(syncSucceeded: true))
    }

    func testPureRuleAcrossLaunchCounts() {
        let eligible = (0...12).filter {
            ReviewPromptService.shouldRequestReview(launchCount: $0, syncSucceeded: true, alreadyRequestedThisLaunch: false)
        }
        XCTAssertEqual(eligible, [3, 6, 9, 12])
    }

    // MARK: - Sync outcome / once per launch

    func testFailedSyncDoesNotRequest() {
        XCTAssertFalse(makeService(onLaunch: 3).shouldRequestReview(syncSucceeded: false))
    }

    func testSecondRequestInSameLaunchIsBlocked() {
        let service = makeService(onLaunch: 3)
        XCTAssertTrue(service.shouldRequestReview(syncSucceeded: true))
        service.markRequestedThisLaunch()
        XCTAssertFalse(service.shouldRequestReview(syncSucceeded: true))
    }

    func testFailedSyncThenSuccessfulSyncInSameLaunchRequests() {
        let service = makeService(onLaunch: 6)
        XCTAssertFalse(service.shouldRequestReview(syncSucceeded: false))
        XCTAssertTrue(service.shouldRequestReview(syncSucceeded: true))
    }

    // MARK: - Sync completion signal

    private func runningState(mode: SyncMode = .full, accounts: Int = 2) -> SyncState {
        var state = SyncState()
        state.isSyncing = true
        state.lastRunMode = mode
        state.lastRunAccountCount = accounts
        return state
    }

    private func finished(_ state: SyncState, error: String? = nil, failedAccounts: Int = 0) -> SyncState {
        var state = state
        state.isSyncing = false
        state.lastError = error
        state.lastRunFailedAccountCount = failedAccounts
        state.lastSyncedAt = .now
        return state
    }

    func testCleanFullSyncCompletionIsSuccessful() {
        let old = runningState()
        XCTAssertTrue(ReviewPromptService.isSuccessfulForegroundSyncCompletion(from: old, to: finished(old)))
    }

    func testRunLevelErrorIsNotSuccessful() {
        let old = runningState()
        XCTAssertFalse(ReviewPromptService.isSuccessfulForegroundSyncCompletion(from: old, to: finished(old, error: "boom")))
    }

    func testPartialAccountFailureIsNotSuccessful() {
        let old = runningState()
        XCTAssertFalse(ReviewPromptService.isSuccessfulForegroundSyncCompletion(from: old, to: finished(old, failedAccounts: 1)))
    }

    func testLightweightSyncIsIgnored() {
        let old = runningState(mode: .lightweight)
        XCTAssertFalse(ReviewPromptService.isSuccessfulForegroundSyncCompletion(from: old, to: finished(old)))
    }

    func testSyncWithoutAccountsIsIgnored() {
        let old = runningState(accounts: 0)
        XCTAssertFalse(ReviewPromptService.isSuccessfulForegroundSyncCompletion(from: old, to: finished(old)))
    }

    func testNonCompletionTransitionIsIgnored() {
        let old = runningState()
        var stillRunning = old
        stillRunning.accountsInProgress = ["a"]
        XCTAssertFalse(ReviewPromptService.isSuccessfulForegroundSyncCompletion(from: old, to: stillRunning))
    }
}
