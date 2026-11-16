import Foundation

/// Why a release write didn't reach Google.
enum GooglePlayReleaseWriteError: LocalizedError, Equatable {
    /// Flag off, app out of scope or a missing `version` rule; already user-facing.
    case denied(String)
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .denied(let message): return message
        case .missingCredentials:  return String(localized: "No credentials found for this account.")
        }
    }
}

/// Commits Google Play release changes for one app and keeps the local caches
/// in step (plan R2, R4).
///
/// Only call `apply` after the user confirmed the change: it commits an edit,
/// which cancels any edit this service account has open for the app elsewhere.
///
/// - On success the committed track replaces that track in the tracks cache
///   (`googleplay-tracks.*`) and the track's edit-free release summaries are
///   read again into `googleplay-releases.*`, so the app list, app detail and
///   release detail show the new state without another Play edit.
/// - On failure nothing is written: both caches keep what they had.
@MainActor
final class GooglePlayReleaseWriter {

    typealias ConnectionFactory = (GooglePlayCredentials) -> any GooglePlayReleaseWriteConnecting

    let account: AccountModel
    let app: GooglePlayAppItem

    private let featureFlags: FeatureFlags
    private let keychain: KeyStorable
    private let storage: PersistentStorable
    private let connectionFactory: ConnectionFactory
    private var connection: (any GooglePlayReleaseWriteConnecting)?

    init(
        account: AccountModel,
        app: GooglePlayAppItem,
        featureFlags: FeatureFlags = .shared,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil,
        connectionFactory: @escaping ConnectionFactory = { GooglePlayAccountConnection(credentials: $0) }
    ) {
        self.account = account
        self.app = app
        self.featureFlags = featureFlags
        self.keychain = keychain
        self.storage = storage ?? SwiftDataStorable.shared
        self.connectionFactory = connectionFactory
    }

    func isAllowed(_ kind: GooglePlayReleaseWriteAccess.Kind) -> Bool {
        GooglePlayReleaseWriteAccess.isAllowed(kind, account: account, app: app, featureFlags: featureFlags)
    }

    /// Commits `change` on `track` and refreshes the caches. Throws
    /// `GooglePlayReleaseWriteError` before any request when not allowed.
    @discardableResult
    func apply(
        _ change: GooglePlayReleaseChange,
        track: String,
        options: GooglePlayCommitOptions
    ) async throws -> GooglePlayTrackModel {
        if let denial = GooglePlayReleaseWriteAccess.denialMessage(
            .init(change), account: account, app: app, featureFlags: featureFlags
        ) {
            throw GooglePlayReleaseWriteError.denied(denial)
        }
        let connection = try liveConnection()

        let committed = try await connection.applyReleaseChange(
            packageName: app.packageName, track: track, change: change, options: options
        )
        Log.print.info("[GooglePlayReleaseWriter] Committed a change on \(track) for \(self.app.packageName)")

        await saveTrack(committed)
        await refreshSummaries(track: track, connection: connection)
        return committed
    }

    /// Bundles already uploaded to Google Play, newest first. Opens a temporary
    /// Play edit: only when the user opens the bundle picker.
    func fetchBundles() async throws -> [GooglePlayBundleModel] {
        if let denial = GooglePlayReleaseWriteAccess.denialMessage(.add, account: account, app: app, featureFlags: featureFlags) {
            throw GooglePlayReleaseWriteError.denied(denial)
        }
        let bundles = try await liveConnection().fetchBundles(packageName: app.packageName)
        return bundles.sorted { $0.versionCodeValue > $1.versionCodeValue }
    }

    // MARK: - Caches

    private var tracksCache: GooglePlayAppCacheStore<GooglePlayTracksCache> {
        GooglePlayAppCacheStore(storage: storage, accountId: account.id, packageName: app.packageName)
    }

    private var summariesCache: GooglePlayAppCacheStore<GooglePlayReleaseSummariesCache> {
        GooglePlayAppCacheStore(storage: storage, accountId: account.id, packageName: app.packageName)
    }

    private func saveTrack(_ committed: GooglePlayTrackModel) async {
        var tracks = await tracksCache.load()?.tracks ?? []
        if let index = tracks.firstIndex(where: { $0.track == committed.track }) {
            tracks[index] = committed
        } else {
            tracks.append(committed)
        }
        await tracksCache.save(GooglePlayTracksCache(accountId: account.id, packageName: app.packageName, tracks: tracks))
    }

    /// Best effort: the commit already succeeded, so a failed refresh only
    /// leaves that track's previous lifecycle states until the next sync.
    private func refreshSummaries(track: String, connection: any GooglePlayReleaseWriteConnecting) async {
        do {
            let fresh = try await connection.fetchReleaseSummaries(packageName: app.packageName, track: track)
            let cached = await summariesCache.load()
            let others = (cached?.summaries ?? []).filter { $0.track != track }
            await summariesCache.save(GooglePlayReleaseSummariesCache(
                accountId: account.id,
                packageName: app.packageName,
                summaries: others + fresh,
                fetchedAt: Date()
            ))
        } catch {
            Log.print.error("[GooglePlayReleaseWriter] Summaries refresh failed after a write: \(error.localizedDescription)")
        }
    }

    private func liveConnection() throws -> any GooglePlayReleaseWriteConnecting {
        if let connection { return connection }
        guard let credentials: GooglePlayCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
            throw GooglePlayReleaseWriteError.missingCredentials
        }
        let connection = connectionFactory(credentials)
        self.connection = connection
        return connection
    }
}
