import XCTest
@testable import StackConnect

/// Covers the templates → reply-composer handoff in `ReviewDetailViewModel`.
///
/// SwiftUI cannot present two sheets from the same view at once, so the composer
/// must only be opened once the templates sheet has finished dismissing. These
/// tests pin that two-step state machine (`selectTemplate` then
/// `applyPendingTemplate`, the latter driven by the sheet's `onDismiss`).
@MainActor
final class ReviewDetailViewModelTemplateTests: XCTestCase {

    private var keychain: MockKeyStorable!
    private var sut: ReviewDetailViewModel!

    override func setUp() async throws {
        try await super.setUp()
        keychain = MockKeyStorable()
        sut = ReviewDetailViewModel(
            review: CustomerReviewModel(id: "r1", rating: 5),
            appName: "App A",
            account: AccountModel(id: "acc1", name: "Test", providerType: .apple),
            keychain: keychain
        )
    }

    override func tearDown() async throws {
        sut = nil
        keychain = nil
        try await super.tearDown()
    }

    private func makeTemplate(body: String = "Thanks for the feedback!") -> ReplyTemplateModel {
        ReplyTemplateModel(accountId: "acc1", title: "Thanks", body: body)
    }

    // MARK: - Step 1: selection

    func testSelectTemplateClosesTemplatesSheetWithoutOpeningComposer() {
        sut.uiState.showTemplatesSheet = true

        sut.selectTemplate(makeTemplate())

        XCTAssertFalse(sut.uiState.showTemplatesSheet, "templates sheet must close first")
        XCTAssertFalse(
            sut.uiState.showReplySheet,
            "composer must not open while the templates sheet is still presented"
        )
        XCTAssertEqual(sut.uiState.pendingTemplateBody, "Thanks for the feedback!")
    }

    // MARK: - Step 2: apply on dismiss

    func testApplyPendingTemplateOpensComposerPreFilledWithTemplateBody() {
        sut.uiState.showTemplatesSheet = true
        sut.selectTemplate(makeTemplate())

        sut.applyPendingTemplate()

        XCTAssertTrue(sut.uiState.showReplySheet)
        XCTAssertEqual(sut.uiState.replyText, "Thanks for the feedback!")
        XCTAssertFalse(sut.uiState.isEditingReply, "a template pre-fill is a new reply, not an edit")
        XCTAssertNil(sut.uiState.pendingTemplateBody, "pending selection must be consumed")
    }

    /// The sheet's `onDismiss` fires on every dismissal, including swipe-down and
    /// Done. Without a pending pick it must not spring the composer open.
    func testApplyPendingTemplateIsNoOpWhenSheetDismissedWithoutSelection() {
        sut.uiState.showTemplatesSheet = true

        sut.applyPendingTemplate()

        XCTAssertFalse(sut.uiState.showReplySheet)
        XCTAssertEqual(sut.uiState.replyText, "")
    }

    func testApplyPendingTemplateTwiceDoesNotReopenComposer() {
        sut.selectTemplate(makeTemplate())
        sut.applyPendingTemplate()

        sut.cancelReplySheet()
        sut.applyPendingTemplate()

        XCTAssertFalse(sut.uiState.showReplySheet, "consumed selection must not replay")
        XCTAssertEqual(sut.uiState.replyText, "")
    }

    // MARK: - Interaction with the composer

    func testTemplateReplacesAnExistingDraft() {
        sut.uiState.replyText = "half-typed draft"

        sut.selectTemplate(makeTemplate(body: "Template body"))
        sut.applyPendingTemplate()

        XCTAssertEqual(sut.uiState.replyText, "Template body")
    }

    func testCancellingComposerClearsPreFilledText() {
        sut.selectTemplate(makeTemplate())
        sut.applyPendingTemplate()

        sut.cancelReplySheet()

        XCTAssertFalse(sut.uiState.showReplySheet)
        XCTAssertEqual(sut.uiState.replyText, "")
    }
}
