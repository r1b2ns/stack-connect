import XCTest
@testable import StackConnect

@MainActor
final class ReplyTemplatesViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var sut: ReplyTemplatesViewModel!

    private let accountId = "acc1"
    private let otherAccountId = "acc2"

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        sut = ReplyTemplatesViewModel(accountId: accountId, storage: storage)
    }

    override func tearDown() async throws {
        sut = nil
        storage = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeTemplate(
        id: String,
        accountId: String? = nil,
        title: String = "Title",
        body: String = "Body",
        createdAt: Date = Date()
    ) -> ReplyTemplateModel {
        ReplyTemplateModel(
            id: id,
            accountId: accountId ?? self.accountId,
            title: title,
            body: body,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func seed(_ templates: ReplyTemplateModel...) async throws {
        for template in templates {
            try await storage.save(template, id: template.id)
        }
    }

    // MARK: - Empty state

    func testLoadWithNoStoredTemplatesLeavesStateEmpty() async {
        await sut.load()

        XCTAssertTrue(sut.uiState.templates.isEmpty)
        XCTAssertTrue(sut.uiState.isEmpty)
        XCTAssertFalse(sut.uiState.isLoading)
    }

    // MARK: - Per-account scope

    func testLoadExcludesTemplatesFromOtherAccounts() async throws {
        try await seed(
            makeTemplate(id: "t1", title: "Mine"),
            makeTemplate(id: "t2", accountId: otherAccountId, title: "Theirs")
        )

        await sut.load()

        XCTAssertEqual(sut.uiState.templates.map(\.id), ["t1"])
        XCTAssertEqual(sut.uiState.templates.map(\.title), ["Mine"])
    }

    func testLoadWithOnlyOtherAccountTemplatesIsEmpty() async throws {
        try await seed(makeTemplate(id: "t1", accountId: otherAccountId))

        await sut.load()

        XCTAssertTrue(sut.uiState.isEmpty)
    }

    // MARK: - Ordering

    /// `fetchAll` has no ordering guarantee (the mock returns dictionary values,
    /// whose order varies run to run), so the ViewModel must impose one.
    func testLoadSortsByCreatedAtNewestFirst() async throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try await seed(
            makeTemplate(id: "oldest", createdAt: base),
            makeTemplate(id: "newest", createdAt: base.addingTimeInterval(200)),
            makeTemplate(id: "middle", createdAt: base.addingTimeInterval(100))
        )

        await sut.load()

        XCTAssertEqual(sut.uiState.templates.map(\.id), ["newest", "middle", "oldest"])
    }

    /// Templates created in the same instant must still get a total order,
    /// otherwise rows can shuffle between loads.
    func testLoadIsDeterministicForIdenticalCreatedAt() async throws {
        let sameDate = Date(timeIntervalSince1970: 1_700_000_000)
        try await seed(
            makeTemplate(id: "c", createdAt: sameDate),
            makeTemplate(id: "a", createdAt: sameDate),
            makeTemplate(id: "b", createdAt: sameDate)
        )

        await sut.load()
        let firstPass = sut.uiState.templates.map(\.id)

        await sut.load()
        let secondPass = sut.uiState.templates.map(\.id)

        XCTAssertEqual(firstPass, ["a", "b", "c"])
        XCTAssertEqual(firstPass, secondPass)
    }

    // MARK: - Create

    func testSavePersistsTemplateAndAddsItToState() async throws {
        await sut.save(title: "Thanks", body: "Thanks for the feedback!")

        XCTAssertEqual(sut.uiState.templates.count, 1)
        let created = try XCTUnwrap(sut.uiState.templates.first)
        XCTAssertEqual(created.title, "Thanks")
        XCTAssertEqual(created.body, "Thanks for the feedback!")
        XCTAssertEqual(created.accountId, accountId)

        // Survives a reload, i.e. it really reached storage.
        await sut.load()
        XCTAssertEqual(sut.uiState.templates.map(\.id), [created.id])
    }

    func testSaveScopesTemplateToTheViewModelsAccount() async throws {
        await sut.save(title: "Thanks", body: "Body")

        let stored: [ReplyTemplateModel] = try await storage.fetchAll(ReplyTemplateModel.self)
        XCTAssertEqual(stored.map(\.accountId), [accountId])
    }

    func testSaveTrimsWhitespace() async throws {
        await sut.save(title: "  Thanks  ", body: "\n Thanks for the feedback! \n")

        let created = try XCTUnwrap(sut.uiState.templates.first)
        XCTAssertEqual(created.title, "Thanks")
        XCTAssertEqual(created.body, "Thanks for the feedback!")
    }

    func testSaveKeepsNewestFirstOrdering() async throws {
        let existing = makeTemplate(
            id: "old",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await seed(existing)
        await sut.load()

        await sut.save(title: "Fresh", body: "Body")

        XCTAssertEqual(sut.uiState.templates.count, 2)
        XCTAssertEqual(sut.uiState.templates.first?.title, "Fresh")
        XCTAssertEqual(sut.uiState.templates.last?.id, "old")
    }

    // MARK: - Update

    func testUpdateMutatesTargetRecordAndBumpsUpdatedAt() async throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let target = makeTemplate(id: "t1", title: "Before", body: "Old body", createdAt: created)
        try await seed(target, makeTemplate(id: "t2", title: "Untouched", createdAt: created.addingTimeInterval(-100)))
        await sut.load()

        await sut.update(target, title: "After", body: "New body")

        let updated = try XCTUnwrap(sut.uiState.templates.first { $0.id == "t1" })
        XCTAssertEqual(updated.title, "After")
        XCTAssertEqual(updated.body, "New body")
        XCTAssertEqual(updated.createdAt, created, "createdAt must be preserved")
        XCTAssertGreaterThan(updated.updatedAt, created, "updatedAt must be bumped")

        let untouched = try XCTUnwrap(sut.uiState.templates.first { $0.id == "t2" })
        XCTAssertEqual(untouched.title, "Untouched")
    }

    func testUpdatePersistsToStorage() async throws {
        let target = makeTemplate(id: "t1", title: "Before", body: "Old body")
        try await seed(target)
        await sut.load()

        await sut.update(target, title: "After", body: "New body")
        await sut.load()

        XCTAssertEqual(sut.uiState.templates.map(\.title), ["After"])
        XCTAssertEqual(sut.uiState.templates.map(\.body), ["New body"])
    }

    func testUpdateDoesNotCreateDuplicateRecord() async throws {
        let target = makeTemplate(id: "t1")
        try await seed(target)
        await sut.load()

        await sut.update(target, title: "After", body: "New body")

        let stored: [ReplyTemplateModel] = try await storage.fetchAll(ReplyTemplateModel.self)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(sut.uiState.templates.count, 1)
    }

    // MARK: - Delete

    func testDeleteRemovesOnlyTheTarget() async throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let target = makeTemplate(id: "t1", title: "Doomed", createdAt: base)
        let survivor = makeTemplate(id: "t2", title: "Survivor", createdAt: base.addingTimeInterval(-100))
        try await seed(target, survivor)
        await sut.load()

        await sut.delete(target)

        XCTAssertEqual(sut.uiState.templates.map(\.id), ["t2"])

        // Confirm the removal reached storage, not just the in-memory state.
        await sut.load()
        XCTAssertEqual(sut.uiState.templates.map(\.id), ["t2"])
    }

    func testDeleteLastTemplateReturnsToEmptyState() async throws {
        let target = makeTemplate(id: "t1")
        try await seed(target)
        await sut.load()

        await sut.delete(target)

        XCTAssertTrue(sut.uiState.isEmpty)
    }

    func testDeleteDoesNotTouchOtherAccountsTemplates() async throws {
        let target = makeTemplate(id: "t1")
        let foreign = makeTemplate(id: "t2", accountId: otherAccountId)
        try await seed(target, foreign)
        await sut.load()

        await sut.delete(target)

        let stored: [ReplyTemplateModel] = try await storage.fetchAll(ReplyTemplateModel.self)
        XCTAssertEqual(stored.map(\.id), ["t2"])
    }

    // MARK: - Form presentation state

    func testFormModeCarriesTemplateForEditAndNilForCreate() {
        let template = makeTemplate(id: "t1")

        XCTAssertNil(ReplyTemplateFormMode.create.template)
        XCTAssertEqual(ReplyTemplateFormMode.edit(template).template, template)
        XCTAssertNotEqual(ReplyTemplateFormMode.create.id, ReplyTemplateFormMode.edit(template).id)
    }
}
