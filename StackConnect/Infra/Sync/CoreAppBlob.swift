import Foundation

/// Thin `Codable` mirror of the Rust core's "app" blob, matching the exact JSON
/// the core emits in `SyncService.sync_apps()`: `{"id","name","bundleId","platform"}`.
///
/// This is intentionally NOT the rich `AppModel`. It exists solely so the
/// `BlobStore` adapter can round-trip the core's blob through `PersistentStorable`
/// without colliding with the app's own `AppModel` persistence (different type
/// name + composite keys). It is persisted under its own derived type name
/// `"CoreAppBlob"` (`String(describing:)`), which is correct and intended.
struct CoreAppBlob: Codable, Equatable {
    let id: String
    let name: String
    let bundleId: String
    let platform: String?
}
