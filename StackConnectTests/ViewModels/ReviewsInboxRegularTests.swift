import XCTest
@testable import StackConnect

// MARK: - Inline composer (ReviewDetailViewModel)

@MainActor
final class ReviewDetailInlineComposerTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var sut: ReviewDetailViewModel!
    private let account = AccountModel(id: "acc1", name: "Team", providerType: .apple)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        sut = makeSUT(review: CustomerReviewModel(id: "r1", rating: 4))
    }

    override func tearDown() async throws {
        sut = nil
        storage = nil
        try await super.tearDown()
    }

    private func makeSUT(review: CustomerReviewModel, account: AccountModel? = nil) -> ReviewDetailViewModel {
        ReviewDetailViewModel(
            review: review,
            appName: "App",
            account: account ?? self.account,
            service: MockCustomerReviewsService(),
            analytics: MockAnalyticsTracker(),
            templatesStorage: storage
        )
    }

    func testLoadTemplatesKeepsOnlyTheAccountsNewestFirst() async throws {
        let old = ReplyTemplateModel(accountId: "acc1", title: "Old", body: "a", createdAt: .distantPast, updatedAt: .distantPast)
        let new = ReplyTemplateModel(accountId: "acc1", title: "New", body: "b")
        let other = ReplyTemplateModel(accountId: "acc2", title: "Other", body: "c")
        for template in [old, new, other] {
            try await storage.save(template, id: template.id)
        }

        await sut.loadTemplates()

        XCTAssertEqual(sut.uiState.templates.map(\.title), ["New", "Old"])
    }

    func testInsertTemplateFillsTheDraftWithoutOpeningASheet() {
        sut.uiState.replyError = "boom"

        sut.insertTemplate(ReplyTemplateModel(accountId: "acc1", title: "Thanks", body: "Thank you!"))

        XCTAssertEqual(sut.uiState.replyText, "Thank you!")
        XCTAssertNil(sut.uiState.replyError)
        XCTAssertFalse(sut.uiState.showReplySheet)
    }

    func testComposerShowsUntilThereIsAReply() {
        XCTAssertTrue(sut.uiState.showsInlineComposer)

        let replied = makeSUT(review: CustomerReviewModel(id: "r2", rating: 5, responseId: "x", responseBody: "Thanks"))
        XCTAssertFalse(replied.uiState.showsInlineComposer)

        replied.beginInlineEdit()
        XCTAssertTrue(replied.uiState.showsInlineComposer)
        XCTAssertTrue(replied.uiState.isEditingReply)
        XCTAssertEqual(replied.uiState.replyText, "Thanks")
        XCTAssertFalse(replied.uiState.showReplySheet, "inline edit never opens the sheet")
    }

    func testComposerHiddenWithoutReplyPermission() {
        let readOnly = AccountModel(id: "acc1", name: "Viewer", providerType: .apple, rules: AccountRules(review: [.view]))
        XCTAssertFalse(makeSUT(review: CustomerReviewModel(id: "r", rating: 1), account: readOnly).uiState.showsInlineComposer)
    }

    func testCanSendNeedsTextAndNoSendInFlight() {
        XCTAssertFalse(sut.uiState.canSendReply)
        sut.uiState.replyText = "   "
        XCTAssertFalse(sut.uiState.canSendReply)
        sut.uiState.replyText = "Hi"
        XCTAssertTrue(sut.uiState.canSendReply)
        sut.uiState.isSending = true
        XCTAssertFalse(sut.uiState.canSendReply)
    }
}

// MARK: - Inbox filter (AllReviewsUiState)

@MainActor
final class AllReviewsFilterTests: XCTestCase {

    private func row(_ id: String, provider: ProviderType, replied: Bool, appId: String) -> DashboardReview {
        let app = AppModel(id: appId, name: appId, bundleId: "b.\(appId)", accountId: "acc")
        return DashboardReview(
            review: CustomerReviewModel(id: id, rating: 3, responseBody: replied ? "ok" : nil),
            provider: provider,
            accountId: "acc",
            appId: appId,
            appName: appId,
            iconUrl: nil,
            platform: nil,
            target: .appStore(app),
            account: nil
        )
    }

    private func state(filter: AllReviewsFilter) -> AllReviewsUiState {
        let rows = [
            row("1", provider: .apple, replied: true, appId: "a"),
            row("2", provider: .apple, replied: false, appId: "a"),
            row("3", provider: .googlePlay, replied: true, appId: "p")
        ]
        var state = AllReviewsUiState()
        state.groups = AllReviewsViewModel.groups(from: rows)
        state.filter = filter
        return state
    }

    func testAllShowsEverything() {
        XCTAssertEqual(state(filter: .all).visibleGroups.flatMap(\.reviews).count, 3)
    }

    func testStoreFiltersKeepOnlyThatStore() {
        XCTAssertEqual(state(filter: .appStore).visibleGroups.map(\.provider), [.apple])
        XCTAssertEqual(state(filter: .googlePlay).visibleGroups.map(\.provider), [.googlePlay])
    }

    func testUnrepliedDropsRepliedReviewsAndEmptyGroups() {
        let unreplied = state(filter: .unreplied)
        XCTAssertEqual(unreplied.visibleGroups.count, 1)
        XCTAssertEqual(unreplied.visibleGroups.first?.reviews.map(\.review.id), ["2"])
        XCTAssertEqual(unreplied.unrepliedCount, 1)
    }
}
