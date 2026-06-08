import Foundation
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Shared Test Mocks

/// In-memory mock for `PersistentStorable` that tracks call counts per type.
/// All access is serialized through `@MainActor` (test class annotation), so no
/// locking is needed.
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
    private(set) var lastFetchReviewsCursor: String?
    private(set) var lastUpsertReplyReviewId: String?
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
        sort: String,
        filterRating: [String]?,
        limit: Int,
        cursor: String?
    ) async throws -> ReviewsPage {
        fetchReviewsCallCount += 1
        lastFetchReviewsAppId = appId
        lastFetchReviewsCursor = cursor
        return try fetchReviewsResult.get()
    }

    func upsertReply(reviewId: String, responseBody: String) async throws {
        upsertReplyCallCount += 1
        lastUpsertReplyReviewId = reviewId
        lastUpsertReplyBody = responseBody
        try upsertReplyResult.get()
    }

    func deleteReply(responseId: String) async throws {
        deleteReplyCallCount += 1
        lastDeleteReplyResponseId = responseId
        try deleteReplyResult.get()
    }
}
