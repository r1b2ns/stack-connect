import Foundation
import StackCore        // PersistentStorable, Log
import StackCoreRust    // BlobStore protocol

/// Bridges the Rust core's synchronous `BlobStore` foreign trait to the app's
/// async `PersistentStorable`. Maps each core `typeName` to a concrete Codable
/// type. The trait methods are synchronous and non-throwing (callback contract),
/// so this bridges to the async/throwing store via a blocking wait and logs —
/// never propagates — failures.
///
/// SAFETY: the core invokes these callbacks from its tokio runtime thread (never
/// the main thread), so the blocking semaphore wait cannot deadlock the UI.
///
/// For the `"app"` type, the adapter MERGES the core's base blob into the app's
/// real `AppModel` (keyed by the composite id `"<accountId>.<appId>"`, the same
/// key `runAccountSync` uses), preserving any existing enrichment/user fields
/// (`iconUrl`, `appStoreState`, `versionString`, `lastModifiedDate`, `isArchived`,
/// `isFavorite`, `hasReviewPending`, `platformVersions`). `CoreAppBlob` is used
/// only as the decode target for the core's blob and the encode shape on read.
final class SwiftDataBlobStore: BlobStore, @unchecked Sendable {

    /// Maps a core `typeName` string to the concrete Codable type used to
    /// round-trip its blob. Today only `"app"` is in use. Adding a new mapping
    /// is a one-line `case` here plus the matching dispatch below.
    private enum CoreType: String {
        case app

        init?(typeName: String) {
            self.init(rawValue: typeName)
        }
    }

    private let storage: PersistentStorable
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storage: PersistentStorable) {
        self.storage = storage
    }

    // MARK: - BlobStore

    func save(typeName: String, id: String, json: String) {
        guard let coreType = CoreType(typeName: typeName) else {
            Log.print.error("SwiftDataBlobStore.save: unknown typeName '\(typeName, privacy: .public)' — ignoring.")
            return
        }

        switch coreType {
        case .app:
            guard let data = json.data(using: .utf8),
                  let blob = try? decoder.decode(CoreAppBlob.self, from: data) else {
                Log.print.error("SwiftDataBlobStore.save: failed to decode CoreAppBlob for id '\(id, privacy: .public)' — ignoring.")
                return
            }
            // The core passes the bare app id; the app keys `AppModel` by the
            // composite "<accountId>.<appId>". Build it from the blob's own fields.
            let compositeId = "\(blob.accountId).\(blob.id)"
            runBlocking { [storage] in
                do {
                    // Merge the core's authoritative base fields into the existing
                    // AppModel (if any), preserving enrichment/user fields so a sync
                    // never drops iconUrl/isFavorite/etc. — mirrors runAccountSync.
                    let existing = try await storage.fetch(AppModel.self, id: compositeId)
                    let merged = AppModel(
                        id: blob.id,
                        name: blob.name,
                        bundleId: blob.bundleId,
                        platform: blob.platform,
                        accountId: blob.accountId,
                        iconUrl: existing?.iconUrl,
                        appStoreState: existing?.appStoreState,
                        versionString: existing?.versionString,
                        lastModifiedDate: existing?.lastModifiedDate,
                        isArchived: existing?.isArchived ?? false,
                        isFavorite: existing?.isFavorite ?? false,
                        hasReviewPending: existing?.hasReviewPending ?? false,
                        platformVersions: existing?.platformVersions
                    )
                    try await storage.save(merged, id: compositeId)
                } catch {
                    Log.print.error("SwiftDataBlobStore.save: persistence failed for id '\(compositeId, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func fetch(typeName: String, id: String) -> String? {
        guard let coreType = CoreType(typeName: typeName) else {
            Log.print.error("SwiftDataBlobStore.fetch: unknown typeName '\(typeName, privacy: .public)' — returning nil.")
            return nil
        }

        switch coreType {
        case .app:
            // `id` is the composite key "<accountId>.<appId>"; load the AppModel and
            // re-emit it as the core's base blob JSON.
            return runBlockingReturning { [storage, encoder] in
                do {
                    guard let app = try await storage.fetch(AppModel.self, id: id) else {
                        return nil
                    }
                    return Self.encodeToJSONString(Self.baseBlob(from: app), using: encoder)
                } catch {
                    Log.print.error("SwiftDataBlobStore.fetch: persistence failed for id '\(id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        }
    }

    func fetchAll(typeName: String) -> [String] {
        guard let coreType = CoreType(typeName: typeName) else {
            Log.print.error("SwiftDataBlobStore.fetchAll: unknown typeName '\(typeName, privacy: .public)' — returning [].")
            return []
        }

        switch coreType {
        case .app:
            // Load all AppModels and re-emit each as the core's base blob JSON.
            return runBlockingReturning { [storage, encoder] in
                do {
                    let apps = try await storage.fetchAll(AppModel.self)
                    return apps.compactMap { Self.encodeToJSONString(Self.baseBlob(from: $0), using: encoder) }
                } catch {
                    Log.print.error("SwiftDataBlobStore.fetchAll: persistence failed: \(error.localizedDescription, privacy: .public)")
                    return []
                }
            } ?? []
        }
    }

    func delete(typeName: String, id: String) {
        guard let coreType = CoreType(typeName: typeName) else {
            Log.print.error("SwiftDataBlobStore.delete: unknown typeName '\(typeName, privacy: .public)' — ignoring.")
            return
        }

        switch coreType {
        case .app:
            // `id` is the composite key "<accountId>.<appId>".
            runBlocking { [storage] in
                do {
                    try await storage.delete(AppModel.self, id: id)
                } catch {
                    Log.print.error("SwiftDataBlobStore.delete: persistence failed for id '\(id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - sync -> async bridge

    /// Runs an async, non-returning operation and blocks the calling (tokio)
    /// thread until it completes. Safe because the core never calls these
    /// callbacks from the main thread.
    private func runBlocking(_ op: @escaping @Sendable () async -> Void) {
        let sem = DispatchSemaphore(value: 0)
        Task {
            await op()
            sem.signal()
        }
        sem.wait()
    }

    /// Value-returning variant of `runBlocking`. The result is captured in a
    /// `Sendable` box guarded by the semaphore, so the read on the calling
    /// thread happens-after the `signal()` on the Task thread.
    private func runBlockingReturning<R: Sendable>(_ op: @escaping @Sendable () async -> R) -> R {
        let sem = DispatchSemaphore(value: 0)
        let box = ResultBox<R>()
        Task {
            box.value = await op()
            sem.signal()
        }
        sem.wait()
        return box.value!
    }

    // MARK: - Helpers

    /// Projects an `AppModel` down to the core's base "app" blob shape
    /// (`{id,name,bundleId,platform,accountId}`) used on `fetch`/`fetchAll`.
    private static func baseBlob(from app: AppModel) -> CoreAppBlob {
        CoreAppBlob(
            id: app.id,
            name: app.name,
            bundleId: app.bundleId,
            platform: app.platform,
            accountId: app.accountId
        )
    }

    private static func encodeToJSONString(_ blob: CoreAppBlob, using encoder: JSONEncoder) -> String? {
        guard let data = try? encoder.encode(blob),
              let string = String(data: data, encoding: .utf8) else {
            Log.print.error("SwiftDataBlobStore: failed to re-encode CoreAppBlob '\(blob.id, privacy: .public)' to JSON.")
            return nil
        }
        return string
    }
}

/// Single-writer / single-reader hand-off box for `runBlockingReturning`. The
/// semaphore provides the memory barrier: the Task writes `value` then signals;
/// the waiter reads `value` only after `wait()` returns, so there is no data race.
private final class ResultBox<R>: @unchecked Sendable {
    var value: R?
}
