import XCTest
@testable import StackConnect

@MainActor
final class SubmissionsViewModelTests: XCTestCase {

    private var sut: SubmissionsViewModel!
    private var mockService: MockSubmissionsService!
    private let account = AccountModel(name: "Apple", providerType: .apple)

    override func setUp() async throws {
        try await super.setUp()
        mockService = MockSubmissionsService()
        sut = makeSUT()
    }

    override func tearDown() async throws {
        sut = nil
        mockService = nil
        try await super.tearDown()
    }

    private func makeSUT() -> SubmissionsViewModel {
        SubmissionsViewModel(
            appId: "app-1",
            appName: "MyApp",
            platform: .ios,
            account: account,
            keychain: MockKeyStorable(),
            service: mockService
        )
    }

    private func submission(
        id: String,
        state: String,
        version: String? = nil,
        date: Date? = nil
    ) -> ReviewSubmissionModel {
        ReviewSubmissionModel(
            id: id,
            appId: "app-1",
            platform: "IOS",
            submittedDate: date,
            state: state,
            versionString: version,
            versionId: nil,
            submittedByName: nil,
            submittedByEmail: nil
        )
    }

    // MARK: - Load

    func testLoadPopulatesSubmissionsAndComputesDrafts() async {
        mockService.submissions = [
            submission(id: "1", state: "READY_FOR_REVIEW"),
            submission(id: "2", state: "READY_FOR_REVIEW"),
            submission(id: "3", state: "COMPLETE")
        ]

        await sut.load()

        XCTAssertEqual(sut.uiState.submissions.count, 3)
        XCTAssertEqual(sut.uiState.drafts.count, 2)
        XCTAssertEqual(mockService.fetchedAppIds, ["app-1"])
        XCTAssertNil(sut.uiState.error)
        XCTAssertFalse(sut.uiState.isLoading)
    }

    func testLoadWithFiveDraftsReachesLimit() async {
        mockService.submissions = (1...5).map { submission(id: "\($0)", state: "READY_FOR_REVIEW") }

        await sut.load()

        XCTAssertEqual(sut.uiState.concurrentCount, 5)
        XCTAssertTrue(sut.uiState.limitReached)
    }

    func testCompleteSubmissionsDoNotCountTowardLimit() async {
        // 4 unfinished + 3 COMPLETE: only the 4 non-terminal ones count.
        mockService.submissions =
            (1...4).map { submission(id: "u\($0)", state: "READY_FOR_REVIEW") } +
            (1...3).map { submission(id: "c\($0)", state: "COMPLETE") }

        await sut.load()

        XCTAssertEqual(sut.uiState.concurrentCount, 4)
        XCTAssertFalse(sut.uiState.limitReached)
    }

    func testLoadFailureSetsError() async {
        mockService.fetchError = TestError.boom

        await sut.load()

        XCTAssertTrue(sut.uiState.submissions.isEmpty)
        XCTAssertNotNil(sut.uiState.error)
        XCTAssertFalse(sut.uiState.isLoading)
    }

    func testLoadSortsDraftsFirst() async {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        mockService.submissions = [
            submission(id: "complete-new", state: "COMPLETE", date: newer),
            submission(id: "draft", state: "READY_FOR_REVIEW"),
            submission(id: "complete-old", state: "COMPLETE", date: older)
        ]

        await sut.load()

        XCTAssertEqual(sut.uiState.submissions.first?.id, "draft")
        XCTAssertEqual(sut.uiState.submissions.last?.id, "complete-old")
    }

    // MARK: - Discard

    func testDiscardSuccessRecordsIdShowsToastAndReloads() async {
        let target = submission(id: "42", state: "READY_FOR_REVIEW")
        mockService.submissions = [target]

        await sut.discard(target)

        XCTAssertEqual(mockService.discardedIds, ["42"])
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Submission discarded"))
        // Reloaded after discard: one fetch triggered by discard's success path.
        XCTAssertEqual(mockService.fetchedAppIds, ["app-1"])
        XCTAssertNil(sut.uiState.error)
        XCTAssertFalse(sut.uiState.discardingIds.contains("42"))
    }

    func testDiscardFailureSetsErrorAndDoesNotReload() async {
        let target = submission(id: "42", state: "READY_FOR_REVIEW")
        mockService.discardError = TestError.boom

        await sut.discard(target)

        XCTAssertEqual(mockService.discardedIds, ["42"])
        XCTAssertNotNil(sut.uiState.error)
        XCTAssertNil(sut.uiState.toastMessage)
        XCTAssertTrue(mockService.fetchedAppIds.isEmpty)
        XCTAssertFalse(sut.uiState.discardingIds.contains("42"))
    }

    // MARK: - Submit

    func testSubmitSuccessRecordsIdShowsToastAndReloads() async {
        let target = submission(id: "7", state: "READY_FOR_REVIEW")
        mockService.submissions = [target]

        await sut.submit(target)

        XCTAssertEqual(mockService.submittedIds, ["7"])
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Submission submitted"))
        XCTAssertEqual(mockService.fetchedAppIds, ["app-1"])
        XCTAssertNil(sut.uiState.error)
    }

    func testSubmitFailureSetsError() async {
        let target = submission(id: "7", state: "READY_FOR_REVIEW")
        mockService.submitError = TestError.boom

        await sut.submit(target)

        XCTAssertEqual(mockService.submittedIds, ["7"])
        XCTAssertNotNil(sut.uiState.error)
        XCTAssertNil(sut.uiState.toastMessage)
    }

    // MARK: - Test error

    private enum TestError: Error { case boom }
}
