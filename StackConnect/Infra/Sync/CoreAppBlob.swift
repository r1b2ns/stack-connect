import Foundation

/// Thin `Codable` mirror of the Rust core's "app" blob, matching the exact JSON
/// the core emits in `SyncService.sync_apps()`:
/// `{"id","name","bundleId","platform","accountId"}` (camelCase; `platform` may be null).
///
/// This is intentionally NOT the rich `AppModel`. It is the decode target for the
/// core's "app" blob and the encode shape the adapter re-emits on `fetch`/`fetchAll`.
/// The adapter uses `accountId` + `id` to build the composite key `"<accountId>.<id>"`
/// under which the real `AppModel` is persisted, then merges the base fields into
/// that `AppModel` (preserving enrichment/user fields).
struct CoreAppBlob: Codable, Equatable {
    let id: String
    let name: String
    let bundleId: String
    let platform: String?
    let accountId: String
}
