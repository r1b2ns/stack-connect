import XCTest
@testable import StackConnect

/// Ordering of the prompts run after a foreground sync: the review request is
/// decided first, and the tip card never shows in a launch that requested one.
@MainActor
final class PostSyncPromptsTests: XCTestCase {

    private let suiteName = "PostSyncPromptsTests.\(UUID().uuidString)"
    private lazy var defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    private var reviewPrompt: ReviewPromptService!
    private var tipJarPrompt: TipJarPromptService!

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        reviewPrompt = nil
        tipJarPrompt = nil
        try await super.tearDown()
    }

    /// A fresh "process" on launch number `launch`, with its launch registered.
    private func makeSUT(onLaunch launch: Int, registerLaunch: Bool = true) -> PostSyncPrompts {
        defaults.set(launch - 1, forKey: ReviewPromptService.launchCountKey)
        reviewPrompt = ReviewPromptService(defaults: defaults)
        if registerLaunch {
            reviewPrompt.registerLaunch()
        }
        tipJarPrompt = TipJarPromptService(defaults: defaults)
        return PostSyncPrompts(reviewPrompt: reviewPrompt, tipJarPrompt: tipJarPrompt)
    }

    private func running() -> SyncState {
        var state = SyncState()
        state.isSyncing = true
        state.lastRunMode = .full
        state.lastRunAccountCount = 2
        return state
    }

    private func finished(_ state: SyncState, error: String? = nil) -> SyncState {
        var state = state
        state.isSyncing = false
        state.lastError = error
        state.lastSyncedAt = .now
        return state
    }

    private func completeSync(_ sut: PostSyncPrompts, error: String? = nil, isSceneActive: Bool = true) -> Bool {
        let old = running()
        return sut.handleSyncStateChange(from: old, to: finished(old, error: error), isSceneActive: isSceneActive)
    }

    // MARK: - Tests

    func testLaunch10WithoutReviewShowsTheCard() {
        let sut = makeSUT(onLaunch: 10)

        XCTAssertFalse(completeSync(sut))
        XCTAssertTrue(tipJarPrompt.isCardVisible)
    }

    func testReviewLaunchRequestsReviewAndSkipsTheCard() {
        // Launch 12 is both a review launch (multiple of 3) and >= 10.
        let sut = makeSUT(onLaunch: 12)

        XCTAssertTrue(completeSync(sut))
        XCTAssertTrue(reviewPrompt.hasRequestedThisLaunch)
        XCTAssertFalse(tipJarPrompt.isCardVisible)
    }

    func testCardStaysOffForTheRestOfAReviewLaunch() {
        let sut = makeSUT(onLaunch: 12)
        XCTAssertTrue(completeSync(sut))

        XCTAssertFalse(completeSync(sut))
        XCTAssertFalse(tipJarPrompt.isCardVisible)
    }

    func testLaunch9ShowsNothing() {
        let sut = makeSUT(onLaunch: 9)

        XCTAssertTrue(completeSync(sut)) // 9 is a review launch.
        XCTAssertFalse(tipJarPrompt.isCardVisible)
    }

    func testFailedSyncShowsNothing() {
        let sut = makeSUT(onLaunch: 10)

        XCTAssertFalse(completeSync(sut, error: "boom"))
        XCTAssertFalse(tipJarPrompt.isCardVisible)
    }

    func testBackgroundSyncShowsNothing() {
        let sut = makeSUT(onLaunch: 12)

        XCTAssertFalse(completeSync(sut, isSceneActive: false))
        XCTAssertFalse(reviewPrompt.hasRequestedThisLaunch)
        XCTAssertFalse(tipJarPrompt.isCardVisible)
    }

    func testUnregisteredLaunchShowsNothing() {
        let sut = makeSUT(onLaunch: 11, registerLaunch: false)

        XCTAssertFalse(completeSync(sut))
        XCTAssertFalse(tipJarPrompt.isCardVisible)
    }

    func testNonCompletionTransitionIsIgnored() {
        let sut = makeSUT(onLaunch: 10)

        XCTAssertFalse(sut.handleSyncStateChange(from: SyncState(), to: running(), isSceneActive: true))
        XCTAssertFalse(tipJarPrompt.isCardVisible)
    }
}
