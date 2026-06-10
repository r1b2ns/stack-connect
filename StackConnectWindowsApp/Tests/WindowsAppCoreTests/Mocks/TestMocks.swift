import Foundation
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Shared Test Mocks

/// In-memory mock for `PersistentStorable` that tracks call counts per type.
/// Storage is accessed sequentially within callers (e.g. `fetchAggregateRating`
/// reads/writes cache outside the concurrent `TaskGroup` which covers only
/// network calls), so no locking is needed.
final class MockStorage: PersistentStorable, @unchecked Sendable {
    private var store: [String: Data] = [:]

    var shouldThrowOnFetch = false
    var shouldThrowOnSave = false
    var shouldThrowOnDelete = false
    private(set) var fetchAllCallCount: [String: Int] = [:]
    private(set) var saveCallCount: Int = 0

    func save<T: Codable>(_ item: T, id: String) async throws {
        if shouldThrowOnSave { throw PersistentStorableError.encodingFailed }
        saveCallCount += 1
        let data = try JSONEncoder().encode(item)
        store["\(String(describing: T.self)).\(id)"] = data
    }

    func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T? {
        if shouldThrowOnFetch { throw PersistentStorableError.decodingFailed }
        guard let data = store["\(String(describing: T.self)).\(id)"] else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T] {
        if shouldThrowOnFetch { throw PersistentStorableError.decodingFailed }
        let key = String(describing: T.self)
        fetchAllCallCount[key, default: 0] += 1
        let datas = store.filter { $0.key.hasPrefix("\(key).") }.values
        return try datas.map { try JSONDecoder().decode(T.self, from: $0) }
    }

    func delete<T: Codable>(_ type: T.Type, id: String) async throws {
        if shouldThrowOnDelete { throw PersistentStorableError.decodingFailed }
        store["\(String(describing: T.self)).\(id)"] = nil
    }

    func deleteAll<T: Codable>(_ type: T.Type) async throws {
        if shouldThrowOnDelete { throw PersistentStorableError.decodingFailed }
        let prefix = "\(String(describing: T.self))."
        for key in store.keys where key.hasPrefix(prefix) { store[key] = nil }
    }
}

/// In-memory mock for `KeyStorable`.
final class MockSecrets: KeyStorable {
    private var store: [String: Any] = [:]

    var allKeys: [String] { Array(store.keys) }

    func string(forKey key: String) -> String? { store[key] as? String }
    func int(forKey key: String) -> Int? { store[key] as? Int }
    func double(forKey key: String) -> Double? { store[key] as? Double }
    func bool(forKey key: String) -> Bool? { store[key] as? Bool }
    func data(forKey key: String) -> Data? { store[key] as? Data }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            store[key] = value
        } else {
            store.removeValue(forKey: key)
        }
    }

    func removeObject(forKey key: String) {
        store.removeValue(forKey: key)
    }
}

// MARK: - Mock Apple Connection

/// Configurable mock for `AppleConnectionProtocol`. Each method returns a
/// canned result (or throws a canned error) and bumps a call counter so tests
/// can assert both behaviour and interaction.
final class MockAppleConnection: AppleConnectionProtocol, @unchecked Sendable {

    // MARK: - Canned Results

    var validateCredentialsResult: Result<Void, Error> = .success(())
    var fetchAppsResult: Result<[AppInfo], Error> = .success([])
    var fetchUsersResult: Result<[UserModel], Error> = .success([])
    var fetchReviewsResult: Result<ReviewsPage, Error> = .success(
        ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
    )
    /// When non-empty, `fetchReviews` pops and returns the first element instead
    /// of using `fetchReviewsResult`. Allows multi-page pagination tests to
    /// return different results on successive calls.
    var fetchReviewsResultQueue: [Result<ReviewsPage, Error>] = []
    var upsertReplyResult: Result<Void, Error> = .success(())
    var deleteReplyResult: Result<Void, Error> = .success(())

    // MARK: - Call Counters

    private(set) var validateCredentialsCallCount = 0
    private(set) var fetchAppsCallCount = 0
    private(set) var fetchUsersCallCount = 0
    private(set) var fetchReviewsCallCount = 0
    private(set) var upsertReplyCallCount = 0
    private(set) var deleteReplyCallCount = 0

    // MARK: - Captured Arguments

    private(set) var lastFetchReviewsAppId: String?
    private(set) var lastFetchReviewsSort: ReviewSortOrder?
    private(set) var lastFetchReviewsFilterRating: [String]?
    private(set) var lastFetchReviewsLimit: Int?
    private(set) var lastFetchReviewsCursor: String?
    private(set) var lastUpsertReplyReviewId: String?
    private(set) var lastUpsertReplyExistingResponseId: String?
    private(set) var lastUpsertReplyBody: String?
    private(set) var lastDeleteReplyResponseId: String?

    // MARK: - AppleConnectionProtocol

    func validateCredentials() async throws {
        validateCredentialsCallCount += 1
        try validateCredentialsResult.get()
    }

    func fetchApps() async throws -> [AppInfo] {
        fetchAppsCallCount += 1
        return try fetchAppsResult.get()
    }

    func fetchUsers() async throws -> [UserModel] {
        fetchUsersCallCount += 1
        return try fetchUsersResult.get()
    }

    func fetchReviews(
        appId: String,
        sort: ReviewSortOrder,
        filterRating: [String]?,
        limit: Int,
        cursor: String?
    ) async throws -> ReviewsPage {
        fetchReviewsCallCount += 1
        lastFetchReviewsAppId = appId
        lastFetchReviewsSort = sort
        lastFetchReviewsFilterRating = filterRating
        lastFetchReviewsLimit = limit
        lastFetchReviewsCursor = cursor
        if !fetchReviewsResultQueue.isEmpty {
            return try fetchReviewsResultQueue.removeFirst().get()
        }
        return try fetchReviewsResult.get()
    }

    func upsertReply(
        reviewId: String,
        existingResponseId: String?,
        responseBody: String
    ) async throws {
        upsertReplyCallCount += 1
        lastUpsertReplyReviewId = reviewId
        lastUpsertReplyExistingResponseId = existingResponseId
        lastUpsertReplyBody = responseBody
        try upsertReplyResult.get()
    }

    func deleteReply(responseId: String) async throws {
        deleteReplyCallCount += 1
        lastDeleteReplyResponseId = responseId
        try deleteReplyResult.get()
    }
}

// MARK: - Suspendable Apple Connection (T-W09)

/// A mock connection that suspends `fetchApps()`, `upsertReply()`, or
/// `deleteReply()` on a continuation, allowing tests to inspect mid-flight
/// state (e.g. `isLoading == true`, `isPending == true`) before resuming the
/// call. All other protocol methods delegate to a canned result or throw.
///
/// Usage (fetchApps):
/// 1. Create the mock.
/// 2. Call the model's async method that triggers `fetchApps()`.
/// 3. `await` the mock's `waitForFetchAppsCall()` to know the call is in-flight.
/// 4. Inspect the model's state (e.g. `isLoading`).
/// 5. Call `resumeFetchApps(with:)` to let the call complete.
///
/// Usage (upsertReply — T-W24):
/// 1. Create the mock.
/// 2. Call the model's async method that triggers `upsertReply()`.
/// 3. `await` the mock's `waitForUpsertReplyCall()` to know the call is in-flight.
/// 4. Inspect the model's state (e.g. `isPending`, `canSubmit`).
/// 5. Call `resumeUpsertReply(with:)` to let the call complete.
///
/// Usage (deleteReply — T-W25):
/// 1. Create the mock.
/// 2. Call the model's async method that triggers `deleteReply()`.
/// 3. `await` the mock's `waitForDeleteReplyCall()` to know the call is in-flight.
/// 4. Inspect the model's state (e.g. `isPending`).
/// 5. Call `resumeDeleteReply(with:)` to let the call complete.
final class SuspendableAppleConnection: AppleConnectionProtocol, @unchecked Sendable {

    // MARK: - fetchApps suspension

    /// Continuation held while `fetchApps()` is suspended.
    private var fetchAppsContinuation: CheckedContinuation<[AppInfo], Error>?

    /// Fulfilled when `fetchApps()` has been called and is suspended.
    private var fetchAppsCalledContinuation: CheckedContinuation<Void, Never>?

    /// Buffered flag: set to `true` when `fetchApps()` is called, so that
    /// `waitForFetchAppsCall()` returns immediately if the call already
    /// happened (eliminates the lost-wakeup race).
    private var fetchAppsWasCalled = false

    /// Awaitable signal that fires once `fetchApps()` is in-flight.
    /// If `fetchApps()` was already called before this method runs, returns
    /// immediately without creating a continuation (race-safe).
    @MainActor
    func waitForFetchAppsCall() async {
        if fetchAppsWasCalled {
            // Signal already buffered — consume it and return immediately.
            fetchAppsWasCalled = false
            return
        }
        await withCheckedContinuation { continuation in
            fetchAppsCalledContinuation = continuation
        }
    }

    /// Safe teardown helper: resumes ALL pending continuations (fetchApps,
    /// upsertReply, and their "called" signals) if they are still in-flight,
    /// otherwise silent no-op. Also clears buffered flags to leave the mock in
    /// a clean state.
    @MainActor
    func resumeIfPending() {
        // Resume the fetchApps data continuation if pending.
        if let continuation = fetchAppsContinuation {
            fetchAppsContinuation = nil
            continuation.resume(returning: [])
        }
        // Resume the "called" signal continuation if pending (defense-in-depth).
        if let calledContinuation = fetchAppsCalledContinuation {
            fetchAppsCalledContinuation = nil
            calledContinuation.resume()
        }
        fetchAppsWasCalled = false

        // Resume the upsertReply data continuation if pending.
        if let continuation = upsertReplyContinuation {
            upsertReplyContinuation = nil
            continuation.resume()
        }
        // Resume the upsertReply "called" signal if pending.
        if let calledContinuation = upsertReplyCalledContinuation {
            upsertReplyCalledContinuation = nil
            calledContinuation.resume()
        }
        upsertReplyWasCalled = false

        // Resume the deleteReply data continuation if pending.
        if let continuation = deleteReplyContinuation {
            deleteReplyContinuation = nil
            continuation.resume()
        }
        // Resume the deleteReply "called" signal if pending.
        if let calledContinuation = deleteReplyCalledContinuation {
            deleteReplyCalledContinuation = nil
            calledContinuation.resume()
        }
        deleteReplyWasCalled = false
    }

    /// Resumes the suspended `fetchApps()` with the given result.
    /// Trips `assertionFailure` if called when no continuation is in-flight.
    func resumeFetchApps(with result: Result<[AppInfo], Error>) {
        guard let continuation = fetchAppsContinuation else {
            assertionFailure("resumeFetchApps called with no in-flight fetchApps continuation")
            return
        }
        fetchAppsContinuation = nil
        switch result {
        case .success(let apps): continuation.resume(returning: apps)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    @MainActor
    func fetchApps() async throws -> [AppInfo] {
        try await withCheckedThrowingContinuation { continuation in
            fetchAppsContinuation = continuation
            fetchAppsWasCalled = true
            fetchAppsCalledContinuation?.resume()
            fetchAppsCalledContinuation = nil
        }
    }

    // MARK: - upsertReply suspension (T-W24)

    /// Continuation held while `upsertReply()` is suspended.
    private var upsertReplyContinuation: CheckedContinuation<Void, Error>?

    /// Fulfilled when `upsertReply()` has been called and is suspended.
    private var upsertReplyCalledContinuation: CheckedContinuation<Void, Never>?

    /// Buffered flag: set to `true` when `upsertReply()` is called, so that
    /// `waitForUpsertReplyCall()` returns immediately if the call already
    /// happened (eliminates the lost-wakeup race).
    private var upsertReplyWasCalled = false

    /// Awaitable signal that fires once `upsertReply()` is in-flight.
    /// If `upsertReply()` was already called before this method runs, returns
    /// immediately without creating a continuation (race-safe).
    @MainActor
    func waitForUpsertReplyCall() async {
        if upsertReplyWasCalled {
            upsertReplyWasCalled = false
            return
        }
        await withCheckedContinuation { continuation in
            upsertReplyCalledContinuation = continuation
        }
    }

    /// Resumes the suspended `upsertReply()` with the given result.
    /// Trips `assertionFailure` if called when no continuation is in-flight.
    func resumeUpsertReply(with result: Result<Void, Error>) {
        guard let continuation = upsertReplyContinuation else {
            assertionFailure("resumeUpsertReply called with no in-flight upsertReply continuation")
            return
        }
        upsertReplyContinuation = nil
        switch result {
        case .success: continuation.resume()
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    // MARK: - deleteReply suspension (T-W25)

    /// Continuation held while `deleteReply()` is suspended.
    private var deleteReplyContinuation: CheckedContinuation<Void, Error>?

    /// Fulfilled when `deleteReply()` has been called and is suspended.
    private var deleteReplyCalledContinuation: CheckedContinuation<Void, Never>?

    /// Buffered flag: set to `true` when `deleteReply()` is called, so that
    /// `waitForDeleteReplyCall()` returns immediately if the call already
    /// happened (eliminates the lost-wakeup race).
    private var deleteReplyWasCalled = false

    /// Awaitable signal that fires once `deleteReply()` is in-flight.
    /// If `deleteReply()` was already called before this method runs, returns
    /// immediately without creating a continuation (race-safe).
    @MainActor
    func waitForDeleteReplyCall() async {
        if deleteReplyWasCalled {
            deleteReplyWasCalled = false
            return
        }
        await withCheckedContinuation { continuation in
            deleteReplyCalledContinuation = continuation
        }
    }

    /// Resumes the suspended `deleteReply()` with the given result.
    /// Trips `assertionFailure` if called when no continuation is in-flight.
    func resumeDeleteReply(with result: Result<Void, Error>) {
        guard let continuation = deleteReplyContinuation else {
            assertionFailure("resumeDeleteReply called with no in-flight deleteReply continuation")
            return
        }
        deleteReplyContinuation = nil
        switch result {
        case .success: continuation.resume()
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    // MARK: - Canned stubs for other protocol methods

    func validateCredentials() async throws {}
    func fetchUsers() async throws -> [UserModel] { [] }
    func fetchReviews(
        appId: String,
        sort: ReviewSortOrder,
        filterRating: [String]?,
        limit: Int,
        cursor: String?
    ) async throws -> ReviewsPage {
        ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
    }
    @MainActor
    func upsertReply(reviewId: String, existingResponseId: String?, responseBody: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            upsertReplyContinuation = continuation
            upsertReplyWasCalled = true
            upsertReplyCalledContinuation?.resume()
            upsertReplyCalledContinuation = nil
        }
    }
    @MainActor
    func deleteReply(responseId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            deleteReplyContinuation = continuation
            deleteReplyWasCalled = true
            deleteReplyCalledContinuation?.resume()
            deleteReplyCalledContinuation = nil
        }
    }
}

// MARK: - Mock Clipboard Provider (T-W26)

/// Configurable mock for `ClipboardProviding`. Captures the last text passed
/// to `setText` and returns a canned success/failure result. Thread-safe
/// enough for single-threaded test scenarios (no locking).
final class MockClipboardProvider: ClipboardProviding, @unchecked Sendable {

    /// Whether `setText` should report success (`true`) or failure (`false`).
    var shouldSucceed: Bool = true

    /// The last text passed to `setText`, captured for assertion.
    private(set) var lastSetText: String?

    /// How many times `setText` was called.
    private(set) var setTextCallCount: Int = 0

    func setText(_ text: String) -> Bool {
        setTextCallCount += 1
        lastSetText = text
        return shouldSucceed
    }
}
