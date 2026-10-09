import Foundation
import StackProtocols
import StackCoreRust

/// Subset of `GooglePlayAccountConnection` the Google Play screens use. Carved out
/// so ViewModels can be unit-tested with a mock connection (no keychain, no
/// network, no Rust core).
protocol GooglePlayAccountConnecting: Sendable {
    /// Token exchange + a 1-item Play Developer Reporting `apps:search`. Success
    /// means the key works and the Reporting API is enabled — it does NOT
    /// guarantee any app is visible yet (Play Console access can take hours to
    /// propagate).
    func validateCredentials() async throws

    /// Every app the service account can see. For Play `id == bundleId ==`
    /// package name and `platform == "ANDROID"`.
    func fetchApps() async throws -> [StackProtocols.AppInfo]
}

// MARK: - App icon seam (public store page, no edit)

/// Looks up an app's store icon on its **public** Google Play page (the core's
/// `AppIcons` capability reads the page's `og:image`).
///
/// Unlike the edit-based reads below, this sends no credentials, mints no OAuth
/// token and never opens a Play edit, so it can't cancel an edit in progress
/// (e.g. a CI upload): it is safe to call automatically, e.g. while the app list
/// loads (plan D18). Best effort: it never throws.
protocol GooglePlayAppIconFetching: Sendable {
    /// A 512 px `https` icon URL (`https://play-lh.googleusercontent.com/…=s512`),
    /// or `nil` when the app isn't public on Google Play (unpublished or unknown
    /// package), the page has no icon, the device is offline or the lookup failed.
    func fetchIconUrl(packageName: String) async -> String?
}

/// What the Play app list needs from one connection: the app listing plus the
/// icon lookup, so a load goes through a single core provider.
typealias GooglePlayAppListConnecting = GooglePlayAccountConnecting & GooglePlayAppIconFetching

// MARK: - App content seams (Android Publisher)
//
// Edit side effect: the Android Publisher API only serves app details, store
// listings and tracks inside an *edit*, so each of these reads inserts a
// temporary edit, reads and deletes it (nothing is committed). Google keeps one
// open edit per service account and app, so a read cancels any edit the same
// service account has open for that app elsewhere — e.g. a CI upload in
// progress. Call them only on an explicit user action (opening that section or
// pulling to refresh it), never automatically or from a background sync.

/// Reads an app's store details. Opens a temporary Play edit (see above).
///
/// Also the "can this service account reach package X?" check: success means
/// yes, `StackError.Http(404)` means no such package, `StackError.Auth` means no
/// access (or the Android Publisher API is disabled).
protocol GooglePlayAppDetailsFetching: Sendable {
    func fetchAppDetails(packageName: String) async throws -> GooglePlayAppDetailsModel
}

/// Reads an app's localized store listings. Opens a temporary Play edit (see above).
protocol GooglePlayStoreListingsFetching: Sendable {
    func fetchStoreListings(packageName: String) async throws -> [GooglePlayStoreListingModel]
}

/// Reads an app's release tracks and releases. Opens a temporary Play edit (see above).
protocol GooglePlayTracksFetching: Sendable {
    func fetchTracks(packageName: String) async throws -> [GooglePlayTrackModel]
}

/// Lists and replies to an app's Google Play reviews (no edit involved).
///
/// Review ids are opaque composites (`{packageName}/{reviewId}`): pass them back
/// unchanged, never parse them.
protocol GooglePlayReviewsConnecting: Sendable {
    /// One page of reviews, newest first (Google's only order). `filterRating`
    /// is applied by the core to each fetched page, so a page can come back short
    /// or even empty while `nextPageToken` is still set. `limit` is clamped to
    /// 1–100.
    func fetchCustomerReviewsPage(
        packageName: String,
        filterRating: Int?,
        limit: Int,
        pageToken: String?
    ) async throws -> CustomerReviewsPageModel

    /// Creates or replaces (upsert) the developer reply. Google rejects replies
    /// longer than about 350 characters with an HTTP 400.
    func replyToReview(reviewId: String, body: String) async throws -> CustomerReviewResponseModel
}

/// Google Play account connection backed by the shared Rust core (plan D1),
/// mirroring `AppleAccountConnection`.
///
/// The stored `GooglePlayCredentials` keep the whole service-account JSON (D2);
/// it is parsed into `GooglePlayServiceAccount` when the core provider is first
/// built. Errors are surfaced unchanged (`GooglePlayServiceAccount.ParseError`,
/// `StackError`, `OfflineError`) — callers turn them into copy with
/// `GooglePlayErrorTranslator`.
final class GooglePlayAccountConnection: AccountConnectionProtocol,
    GooglePlayAccountConnecting,
    GooglePlayAppIconFetching,
    GooglePlayAppDetailsFetching,
    GooglePlayStoreListingsFetching,
    GooglePlayTracksFetching,
    GooglePlayReviewsConnecting,
    @unchecked Sendable {

    private let credentials: GooglePlayCredentials

    /// Resolves feature flags (e.g. `useRustCoreDebugLogging`). Injected for testability.
    private let featureFlags: FeatureFlags

    /// Synchronous connectivity probe. Unlike App Store Connect there is no
    /// offline-capable read here — every call is a live Google request — so
    /// every method fails fast offline (callers keep their cache) instead of
    /// waiting for a network timeout.
    private let connectivity: ConnectivityProviding

    /// Serialises the lazy build of `rustProvider`: `@unchecked Sendable` means
    /// two tasks may ask for the provider at once.
    private let lock = NSLock()

    /// Lazily-built Rust core provider, reused across calls on this connection.
    private var rustProvider: StackCoreRust.Provider?

    init(
        credentials: GooglePlayCredentials,
        featureFlags: FeatureFlags = .shared,
        connectivity: ConnectivityProviding = ConnectivityMonitor.shared
    ) {
        self.credentials = credentials
        self.featureFlags = featureFlags
        self.connectivity = connectivity
    }

    /// Throws `OfflineError.noConnection` when the device is offline so network
    /// calls fail fast (and with friendly copy).
    private func requireOnline() throws {
        if !connectivity.isCurrentlyOnline() {
            throw OfflineError.noConnection
        }
    }

    // MARK: - AccountConnectionProtocol

    func validateCredentials() async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        try await callRustCore { try await provider.validate() }
        Log.print.info("[GooglePlay] Credentials validated successfully (Rust core)")
    }

    func fetchApps() async throws -> [StackProtocols.AppInfo] {
        try requireOnline()
        let provider = try rustCoreProvider()
        let coreApps = try await callRustCore { try await provider.fetchApps() }
        let apps = coreApps.map { app in
            StackProtocols.AppInfo(
                id: app.id,
                name: app.name,
                bundleId: app.bundleId,
                platform: app.platform
            )
        }
        Log.print.info("[GooglePlay] Fetched \(apps.count) apps (Rust core)")
        return apps
    }

    // MARK: - App icon (public store page, see the seam docs)

    /// Mirrors `AppleAccountConnection.fetchIconUrl(appId:)`: best effort, so an
    /// unsupported capability, an offline device or any core error is logged at
    /// info level (a missing icon is cosmetic, not a failure) and becomes `nil`.
    /// Uses the connection's single lazily-built provider.
    func fetchIconUrl(packageName: String) async -> String? {
        do {
            try requireOnline()
            let provider = try rustCoreProvider()
            guard let appIcons = provider.appIcons() else {
                Log.print.info("[GooglePlay] App Icons capability is not available; no icon for \(packageName)")
                return nil
            }
            guard let iconUrl = try await appIcons.fetchIconUrl(appId: packageName) else {
                Log.print.info("[GooglePlay] No public store icon for \(packageName) (Rust core)")
                return nil
            }
            // Defense in depth: the icon is loaded straight into an image view,
            // so only ever hand back a remote https URL.
            guard URL(string: iconUrl)?.scheme?.lowercased() == "https" else {
                Log.print.info("[GooglePlay] Ignoring non-https icon URL for \(packageName)")
                return nil
            }
            return iconUrl
        } catch {
            Log.print.info("[GooglePlay] Icon fetch failed for \(packageName) (Rust core): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - App content (edit-based, see the seam docs)

    func fetchAppDetails(packageName: String) async throws -> GooglePlayAppDetailsModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let appDetails = provider.appDetails() else {
            throw translate(.Unsupported(message: "App Details capability is not available for this provider."))
        }
        let info = try await callRustCore { try await appDetails.fetchAppDetails(appId: packageName) }
        Log.print.info("[GooglePlay] Fetched app details for \(packageName) (Rust core)")
        return Self.mapAppDetails(info)
    }

    func fetchStoreListings(packageName: String) async throws -> [GooglePlayStoreListingModel] {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let storeListings = provider.storeListings() else {
            throw translate(.Unsupported(message: "Store Listings capability is not available for this provider."))
        }
        let infos = try await callRustCore { try await storeListings.fetchStoreListings(appId: packageName) }
        Log.print.info("[GooglePlay] Fetched \(infos.count) store listings for \(packageName) (Rust core)")
        return infos.map(Self.mapStoreListing)
    }

    func fetchTracks(packageName: String) async throws -> [GooglePlayTrackModel] {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let tracks = provider.tracks() else {
            throw translate(.Unsupported(message: "Tracks capability is not available for this provider."))
        }
        let infos = try await callRustCore { try await tracks.fetchTracks(appId: packageName) }
        Log.print.info("[GooglePlay] Fetched \(infos.count) tracks for \(packageName) (Rust core)")
        return infos.map(Self.mapTrack)
    }

    // MARK: - Reviews

    /// Google's own order (most recent first) is the only sort Play supports;
    /// the core rejects anything else with `Unsupported`.
    static let reviewsSort = "-createdDate"

    /// The core clamps the page size to this range too; clamping here keeps the
    /// `UInt32` conversion safe.
    static let reviewsPageSizeRange = 1...100

    func fetchCustomerReviewsPage(
        packageName: String,
        filterRating: Int?,
        limit: Int,
        pageToken: String?
    ) async throws -> CustomerReviewsPageModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let reviews = provider.reviews() else {
            throw translate(.Unsupported(message: "Reviews capability is not available for this provider."))
        }
        let pageSize = UInt32(min(max(limit, Self.reviewsPageSizeRange.lowerBound), Self.reviewsPageSizeRange.upperBound))
        let page = try await callRustCore {
            try await reviews.fetchCustomerReviewsPage(
                appId: packageName,
                sort: Self.reviewsSort,
                filterRating: filterRating.map { [String($0)] } ?? [],
                limit: pageSize,
                pageToken: pageToken
            )
        }
        let model = CoreReviewMapper.page(page)
        Log.print.info("[GooglePlay] Fetched \(model.reviews.count) reviews for \(packageName), hasMore: \(model.hasNextPage) (Rust core)")
        return model
    }

    func replyToReview(reviewId: String, body: String) async throws -> CustomerReviewResponseModel {
        try requireOnline()
        let provider = try rustCoreProvider()
        guard let reviews = provider.reviews() else {
            throw translate(.Unsupported(message: "Reviews capability is not available for this provider."))
        }
        let response = try await callRustCore { try await reviews.replyToReview(reviewId: reviewId, body: body) }
        // The review id is an opaque composite that embeds the package name — fine
        // to log (no secrets), but never parsed.
        Log.print.info("[GooglePlay] Replied to review \(reviewId) (Rust core)")
        return CoreReviewMapper.reviewResponse(response)
    }

    func disconnect() {
        lock.withLock { rustProvider = nil }
        Log.print.info("[GooglePlay] Disconnected")
    }

    // MARK: - Rust core

    /// Lazily builds and caches the Rust core `Provider` for Google Play.
    ///
    /// `connect(...)` is synchronous and offline: it reads the three secrets via
    /// `GooglePlayCredentialStore` and parses the RSA key eagerly, so a bad key
    /// throws `StackError.InvalidCredentials` here. The `accountId` is the
    /// service account's `client_email` (plan D3) — a stable, credential-derived
    /// identifier the read-only store ignores.
    private func rustCoreProvider() throws -> StackCoreRust.Provider {
        try lock.withLock {
            if let rustProvider {
                return rustProvider
            }
            let serviceAccount = try GooglePlayServiceAccount(credentials: credentials)
            do {
                let provider = try connect(
                    kind: .googlePlay,
                    accountId: serviceAccount.clientEmail,
                    store: GooglePlayCredentialStore(serviceAccount: serviceAccount),
                    debugLogger: featureFlags.isEnabled(.useRustCoreDebugLogging) ? RustCoreDebugLogger() : nil
                )
                rustProvider = provider
                return provider
            } catch let error as StackError {
                throw translate(error)
            }
        }
    }

    /// Runs a Rust core async call, routing `StackError` through `translate`.
    private func callRustCore<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as StackError {
            throw translate(error)
        }
    }

    /// Logs a Rust-core error at the boundary and preserves the typed error, so
    /// `GooglePlayErrorTranslator` can still map it to user-facing copy.
    private func translate(_ error: StackError) -> Error {
        Log.print.error("[GooglePlay] Rust core error: \(error.localizedDescription)")
        return error
    }

    // MARK: - Mapping

    /// `AppDetailsInfo.appId` is the package name for Google Play.
    static func mapAppDetails(_ info: StackCoreRust.AppDetailsInfo) -> GooglePlayAppDetailsModel {
        GooglePlayAppDetailsModel(
            packageName: info.appId,
            defaultLanguage: info.defaultLanguage,
            contactEmail: info.contactEmail,
            contactPhone: info.contactPhone,
            contactWebsite: info.contactWebsite
        )
    }

    static func mapStoreListing(_ info: StackCoreRust.StoreListingInfo) -> GooglePlayStoreListingModel {
        GooglePlayStoreListingModel(
            language: info.language,
            title: info.title,
            shortDescription: info.shortDescription,
            fullDescription: info.fullDescription,
            video: info.video
        )
    }

    static func mapTrack(_ info: StackCoreRust.TrackInfo) -> GooglePlayTrackModel {
        GooglePlayTrackModel(track: info.track, releases: info.releases.map(mapRelease))
    }

    /// Raw Play values pass through; only the status is typed (unknown values
    /// become `.unknown`) and the priority widened to `Int`.
    static func mapRelease(_ info: StackCoreRust.TrackReleaseInfo) -> GooglePlayReleaseModel {
        GooglePlayReleaseModel(
            name: info.name,
            status: GooglePlayReleaseStatus(raw: info.status),
            versionCodes: info.versionCodes,
            userFraction: info.userFraction,
            releaseNotes: info.releaseNotes.map {
                GooglePlayLocalizedTextModel(language: $0.language, text: $0.text)
            },
            inAppUpdatePriority: info.inAppUpdatePriority.map(Int.init)
        )
    }
}
