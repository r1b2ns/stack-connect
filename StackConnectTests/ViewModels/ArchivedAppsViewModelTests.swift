import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class ArchivedAppsViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var analytics: MockAnalyticsTracker!
    private var sut: ArchivedAppsViewModel!
    private let account = AccountModel(name: "Team", providerType: .apple)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        analytics = MockAnalyticsTracker()
        sut = ArchivedAppsViewModel(account: account, storage: storage, keychain: MockKeyStorable(), analytics: analytics)
        var app = AppModel(id: "a", name: "A", bundleId: "com.a", accountId: account.id)
        app.isArchived = true
        try await storage.save(app, id: "\(account.id).a")
        await sut.loadApps()
    }

    override func tearDown() async throws {
        sut = nil
        analytics = nil
        storage = nil
        try await super.tearDown()
    }

    func testLoadAppsShowsArchivedAppsWithoutTracking() {
        XCTAssertEqual(sut.uiState.apps.map(\.id), ["a"])
        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testRefreshWithoutCredentialsTracksFailure() async {
        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .archivedApps, result: .failure)])
    }

    func testUnarchiveTracksTapAndSuccess() async throws {
        let app = try XCTUnwrap(sut.uiState.apps.first)

        await sut.unarchive(app: app)

        XCTAssertEqual(analytics.taps(of: .unarchive), [.buttonTap(.unarchive, on: .archivedApps)])
        XCTAssertEqual(analytics.actions(of: .toggleArchive), [
            .action(.toggleArchive, on: .archivedApps, result: .success, parameters: [AnalyticsParameterKey.enabled: .bool(false)])
        ])
    }

    func testUnarchiveTracksFailureWhenSaveFails() async throws {
        let app = try XCTUnwrap(sut.uiState.apps.first)
        await storage.failSave(AppModel.self)

        await sut.unarchive(app: app)

        XCTAssertEqual(analytics.results(of: .toggleArchive), [.failure])
    }
}
