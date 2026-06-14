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
/// Scope: this adapter is a reusable, testable bridge only. It is NOT yet wired
/// into the sync pipeline (`runAccountSync` / `SyncService`); today it is
/// exercised solely by its own unit tests.
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
            runBlocking { [storage] in
                do {
                    try await storage.save(blob, id: id)
                } catch {
                    Log.print.error("SwiftDataBlobStore.save: persistence failed for id '\(id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
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
            return runBlockingReturning { [storage, encoder] in
                do {
                    guard let blob = try await storage.fetch(CoreAppBlob.self, id: id) else {
                        return nil
                    }
                    return Self.encodeToJSONString(blob, using: encoder)
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
            return runBlockingReturning { [storage, encoder] in
                do {
                    let blobs = try await storage.fetchAll(CoreAppBlob.self)
                    return blobs.compactMap { Self.encodeToJSONString($0, using: encoder) }
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
            runBlocking { [storage] in
                do {
                    try await storage.delete(CoreAppBlob.self, id: id)
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
