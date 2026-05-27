import XCTest
@testable import StackConnect

@MainActor
final class AppStoreReviewCountWidgetTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var sut: AppStoreReviewCountWidget!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        sut = AppStoreReviewCountWidget(
            configuration: HomeWidgetConfiguration(kind: .appStoreReviewCount),
            storage: storage
        )
    }

    override func tearDown() async throws {
        sut = nil
        storage = nil
        try await super.tearDown()
    }

    func testLoadCountsInReviewAndAwaitingApps() async throws {
        try await storage.save(makeApp(id: "1", state: .inReview), id: "1")
        try await storage.save(makeApp(id: "2", state: .waitingForReview), id: "2")
        try await storage.save(makeApp(id: "3", state: .pendingDeveloperRelease), id: "3")
        try await storage.save(makeApp(id: "4", state: .readyForSale), id: "4")

        await sut.load()

        XCTAssertEqual(sut.inReviewCount, 2)
        XCTAssertEqual(sut.awaitingReleaseCount, 1)
    }

    func testLoadIncludesReadyForSaleWithActivePhased() async throws {
        try await storage.save(makeApp(id: "1", state: .readyForSale), id: "1")
        try await storage.save(
            PhasedReleaseModel(id: "phased.1", state: .active),
            id: "phased.1"
        )

        await sut.load()

        XCTAssertEqual(sut.inReviewCount, 0)
        XCTAssertEqual(sut.awaitingReleaseCount, 1)
    }

    func testLoadIgnoresArchivedApps() async throws {
        try await storage.save(
            makeApp(id: "1", state: .inReview, isArchived: true),
            id: "1"
        )

        await sut.load()

        XCTAssertEqual(sut.inReviewCount, 0)
        XCTAssertEqual(sut.awaitingReleaseCount, 0)
    }

    func testLoadIgnoresReadyForSaleWithoutPhased() async throws {
        try await storage.save(makeApp(id: "1", state: .readyForSale), id: "1")

        await sut.load()

        XCTAssertEqual(sut.inReviewCount, 0)
        XCTAssertEqual(sut.awaitingReleaseCount, 0)
    }

    func testLoadWithEmptyStorageReturnsZero() async {
        await sut.load()

        XCTAssertEqual(sut.inReviewCount, 0)
        XCTAssertEqual(sut.awaitingReleaseCount, 0)
    }

    // MARK: - Helpers

    private func makeApp(id: String, state: AppStoreState, isArchived: Bool = false) -> AppModel {
        AppModel(
            id: id,
            name: "App \(id)",
            bundleId: "com.test.\(id)",
            accountId: "acc",
            appStoreState: state,
            isArchived: isArchived
        )
    }
}
