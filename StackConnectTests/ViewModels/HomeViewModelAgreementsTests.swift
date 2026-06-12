import XCTest
@testable import StackConnect

@MainActor
final class HomeViewModelAgreementsTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var sut: HomeViewModel!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        sut = HomeViewModel(
            storage: storage,
            keychain: MockKeyStorable(),
            preferences: MockKeyStorable(),
            syncService: .shared
        )
    }

    override func tearDown() async throws {
        sut = nil
        storage = nil
        try await super.tearDown()
    }

    func testOnlyFlaggedAppleAccountSurfacesInPendingAgreements() async throws {
        let flagged = AccountModel(
            name: "Flagged",
            providerType: .apple,
            hasPendingAgreements: true,
            pendingAgreementsDetectedAt: .now
        )
        let clean = AccountModel(name: "Clean", providerType: .apple)
        try await storage.save(flagged, id: flagged.id)
        try await storage.save(clean, id: clean.id)

        await sut.loadDashboard()

        XCTAssertEqual(sut.uiState.pendingAgreementsAccounts.map(\.id), [flagged.id])
    }

    func testNonAppleFlaggedAccountIsIgnored() async throws {
        // Defensive: only Apple accounts can have pending ASC agreements.
        let firebase = AccountModel(
            name: "Firebase",
            providerType: .firebase,
            hasPendingAgreements: true,
            pendingAgreementsDetectedAt: .now
        )
        try await storage.save(firebase, id: firebase.id)

        await sut.loadDashboard()

        XCTAssertTrue(sut.uiState.pendingAgreementsAccounts.isEmpty)
    }

    func testDismissRemovesBannerAndStaysDismissedForSession() async throws {
        let flagged = AccountModel(
            name: "Flagged",
            providerType: .apple,
            hasPendingAgreements: true,
            pendingAgreementsDetectedAt: .now
        )
        try await storage.save(flagged, id: flagged.id)

        await sut.loadDashboard()
        XCTAssertEqual(sut.uiState.pendingAgreementsAccounts.count, 1)

        sut.dismissPendingAgreements(accountId: flagged.id)
        XCTAssertTrue(sut.uiState.pendingAgreementsAccounts.isEmpty)

        // Re-loading the dashboard must not bring the dismissed banner back.
        await sut.loadDashboard()
        XCTAssertTrue(sut.uiState.pendingAgreementsAccounts.isEmpty)
    }
}
