import Foundation

/// A cached section of one Google Play app's detail, scoped to an account and a
/// package name.
///
/// Every section is stored on its own (`"<keyPrefix>.<accountId>.<packageName>"`)
/// so opening one section never rewrites another. The entry carries its own
/// `accountId`, which lets `AccountCascadeDeleter` find every entry of a deleted
/// account with a `fetchAll` — including apps that are no longer in the cached
/// app list.
protocol GooglePlayAppScopedCache: Codable, Sendable {
    /// Storage id prefix, unique per section. Never change it: it is the stable
    /// storage id of data already on users' devices.
    static var keyPrefix: String { get }
    var accountId: String { get }
    var packageName: String { get }
}

extension GooglePlayAppScopedCache {

    /// Stable storage id of this section for one account + package.
    static func cacheKey(accountId: String, packageName: String) -> String {
        "\(keyPrefix).\(accountId).\(packageName)"
    }

    var cacheKey: String {
        Self.cacheKey(accountId: accountId, packageName: packageName)
    }
}

/// A cached edit-based section (app details, store listings, tracks), read and
/// written generically by `GooglePlayAppSectionLoader`. `content` is what the
/// API returned for the section; only its stored property is encoded, so the
/// storage format doesn't change.
protocol GooglePlayAppSectionCache: GooglePlayAppScopedCache {
    associatedtype Content: Sendable
    var content: Content { get }
    init(accountId: String, packageName: String, content: Content)
}

/// Cached App Details section (`GooglePlayAppDetailsModel`).
struct GooglePlayAppDetailsCache: GooglePlayAppScopedCache {
    static let keyPrefix = "googleplay-details"
    let accountId: String
    let packageName: String
    var details: GooglePlayAppDetailsModel
}

extension GooglePlayAppDetailsCache: GooglePlayAppSectionCache {
    var content: GooglePlayAppDetailsModel { details }

    init(accountId: String, packageName: String, content: GooglePlayAppDetailsModel) {
        self.init(accountId: accountId, packageName: packageName, details: content)
    }
}

/// Cached Store Listings section.
struct GooglePlayStoreListingsCache: GooglePlayAppScopedCache {
    static let keyPrefix = "googleplay-listings"
    let accountId: String
    let packageName: String
    var listings: [GooglePlayStoreListingModel]
}

extension GooglePlayStoreListingsCache: GooglePlayAppSectionCache {
    var content: [GooglePlayStoreListingModel] { listings }

    init(accountId: String, packageName: String, content: [GooglePlayStoreListingModel]) {
        self.init(accountId: accountId, packageName: packageName, listings: content)
    }
}

/// Cached Tracks & Releases section.
struct GooglePlayTracksCache: GooglePlayAppScopedCache {
    static let keyPrefix = "googleplay-tracks"
    let accountId: String
    let packageName: String
    var tracks: [GooglePlayTrackModel]
}

extension GooglePlayTracksCache: GooglePlayAppSectionCache {
    var content: [GooglePlayTrackModel] { tracks }

    init(accountId: String, packageName: String, content: [GooglePlayTrackModel]) {
        self.init(accountId: accountId, packageName: packageName, tracks: content)
    }
}

/// Cached first page of the app's reviews (unfiltered, newest first).
struct GooglePlayReviewsCache: GooglePlayAppScopedCache {
    static let keyPrefix = "googleplay-reviews"
    let accountId: String
    let packageName: String
    var reviews: [CustomerReviewModel]
}

/// Reads and writes one section's cache entry for one account + package.
///
/// Failures are logged and swallowed: a missing cache only means the screen
/// waits for the API, and a failed write is retried on the next sync.
struct GooglePlayAppCacheStore<Entry: GooglePlayAppScopedCache>: Sendable {

    let storage: PersistentStorable
    let accountId: String
    let packageName: String

    var key: String {
        Entry.cacheKey(accountId: accountId, packageName: packageName)
    }

    func load() async -> Entry? {
        do {
            return try await storage.fetch(Entry.self, id: key)
        } catch {
            Log.print.error("[GooglePlayCache] Load failed for \(Entry.keyPrefix): \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ entry: Entry) async {
        do {
            try await storage.save(entry, id: key)
        } catch {
            Log.print.error("[GooglePlayCache] Save failed for \(Entry.keyPrefix): \(error.localizedDescription)")
        }
    }
}
