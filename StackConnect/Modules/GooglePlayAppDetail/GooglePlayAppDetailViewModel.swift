import Foundation

// MARK: - Protocol

@MainActor
protocol GooglePlayAppDetailViewModelProtocol: ObservableObject {
    var uiState: GooglePlayAppDetailUiState { get set }
    /// Reads the local cache only — this screen never calls Google.
    func load() async
    /// `nil` when the user may open `section`, otherwise why not. A pure query.
    func denial(for section: GooglePlayAppDetailSection) -> String?
    /// Shows the "Permission Denied" alert with `message`.
    func presentDenial(_ message: String)
}

// MARK: - Sections

/// Menu entries of a Google Play app.
enum GooglePlayAppDetailSection: CaseIterable, Identifiable {
    case ratingsReviews
    case storeListings
    case tracks
    case appDetails

    var id: Self { self }

    var title: String {
        switch self {
        case .ratingsReviews: return String(localized: "Ratings & Reviews")
        case .storeListings:  return String(localized: "Store Listings")
        case .tracks:         return String(localized: "Tracks & Releases")
        case .appDetails:     return String(localized: "App Details")
        }
    }

    var icon: String {
        switch self {
        case .ratingsReviews: return "star.fill"
        case .storeListings:  return "text.below.photo.fill"
        case .tracks:         return "square.stack.3d.up.fill"
        case .appDetails:     return "info.circle.fill"
        }
    }

    /// Read through a temporary Play edit, which cancels an edit the same
    /// service account has open for the app (see `GooglePlayAppDetailsFetching`).
    /// These sections load only when the user opens them.
    var opensPlayEdit: Bool {
        self != .ratingsReviews
    }

    /// Account rule needed to view the section.
    var requiredResource: AccountRuleResource {
        switch self {
        case .ratingsReviews:              return .review
        case .tracks:                      return .version
        case .storeListings, .appDetails:  return .apps
        }
    }
}

// MARK: - Releases

/// One release row of the app detail's track sections (prototype screen 2).
struct GooglePlayAppDetailReleaseRow: Hashable, Identifiable {
    let key: GooglePlayReleaseKey
    /// Short release name ("4.2.0").
    let title: String
    let versionCodes: [String]
    /// From `releases.list`; `nil` when only the tracks cache knows the release.
    let lifecycleState: GooglePlayReleaseLifecycleState?
    /// From the tracks cache (edit-based), when it holds this release.
    let release: GooglePlayReleaseModel?

    var id: GooglePlayReleaseKey { key }

    /// Status badge ("Rolling out", "Completed"…), tracks cache only.
    var status: GooglePlayReleaseStatus? { release?.status }

    /// Staged rollout fraction, tracks cache only, while rolling out or halted.
    var rolloutFraction: Double? { release?.rolloutFraction }
}

/// A track section of the app detail: its releases, newest first.
struct GooglePlayAppDetailTrackSection: Hashable, Identifiable {
    let track: String
    let rows: [GooglePlayAppDetailReleaseRow]

    var id: String { track }
    var kind: GooglePlayTrackKind { GooglePlayTrackKind(track: track) }

    /// Sections from the cached release summaries (plan R1), each row
    /// enriched with its status and rollout from the tracks cache when that
    /// holds the same release (R7). Without summaries, the tracks cache alone
    /// (no lifecycle line). Tracks without a release are left out.
    static func build(
        summaries: GooglePlayReleaseSummariesCache?,
        tracks: [GooglePlayTrackModel]?
    ) -> [GooglePlayAppDetailTrackSection] {
        var cachedReleases: [GooglePlayReleaseKey: GooglePlayReleaseModel] = [:]
        for track in tracks ?? [] {
            for release in track.releases {
                cachedReleases[release.releaseKey(track: track.track)] = release
            }
        }

        if let summaries, !summaries.summaries.isEmpty {
            return summaries.tracks.map { entry in
                let titles = disambiguatedTitles(entry.releases.map { ($0.shortName, $0.name) })
                return GooglePlayAppDetailTrackSection(track: entry.track, rows: zip(entry.releases, titles).map { summary, title in
                    GooglePlayAppDetailReleaseRow(
                        key: summary.releaseKey,
                        title: title,
                        versionCodes: summary.versionCodes,
                        lifecycleState: summary.lifecycleState,
                        release: cachedReleases[summary.releaseKey]
                    )
                })
            }
        }

        return GooglePlayTrackModel.sorted(tracks ?? []).compactMap { track in
            guard !track.releases.isEmpty else { return nil }
            let titles = disambiguatedTitles(track.releases.map { ($0.shortName, $0.name) })
            return GooglePlayAppDetailTrackSection(track: track.track, rows: zip(track.releases, titles).map { release, title in
                GooglePlayAppDetailReleaseRow(
                    key: release.releaseKey(track: track.track),
                    title: title,
                    versionCodes: release.versionCodes,
                    lifecycleState: nil,
                    release: release
                )
            })
        }
    }
}

extension GooglePlayAppDetailTrackSection {

    /// Short names ("4.3.0"), except where two releases of the section share
    /// one: those keep their full name ("4.3.0 (4305)").
    static func disambiguatedTitles(_ names: [(short: String, full: String?)]) -> [String] {
        let counts = Dictionary(names.map { ($0.short, 1) }, uniquingKeysWith: +)
        return names.map { name in
            guard counts[name.short, default: 0] > 1, let full = name.full, !full.isEmpty else { return name.short }
            return full
        }
    }
}

// MARK: - UiState

struct GooglePlayAppDetailUiState {
    var account: AccountModel
    var app: GooglePlayAppItem
    /// Default store-listing language from the cached App Details, if any.
    var defaultLanguage: String?
    var permissionDeniedMessage: String?
    /// One section per track with a release, from the caches only.
    var releaseSections: [GooglePlayAppDetailTrackSection] = []

    /// Release sections and "See all tracks" need the `version` rule (R5).
    var canViewReleases: Bool {
        account.canView(.version)
    }

    /// Per-app scope of an imported account. The app list never shows an app
    /// outside it; this guards the screen itself too.
    var isAppInScope: Bool {
        account.allowsApp(bundleId: app.packageName)
    }

    let reviewSections: [GooglePlayAppDetailSection] = [.ratingsReviews]
    /// The edit-based store sections, grouped under the edit side-effect
    /// footer. Tracks are reached through "See all tracks" under the release
    /// sections.
    let storeSections: [GooglePlayAppDetailSection] = [.storeListings, .appDetails]
}

// MARK: - Implementation

/// Menu of a Google Play app.
///
/// Edit side-effect mitigation: store listings, tracks and app details are read
/// through a temporary Play edit, so nothing here (nor in any background path)
/// fetches them. Each section loads only when the user opens it; this screen
/// only reads the local caches — the release status comes from the summaries
/// the app list fetched (edit-free), the rollout and status badges from the
/// tracks cache when the user opened Tracks before.
@MainActor
final class GooglePlayAppDetailViewModel: GooglePlayAppDetailViewModelProtocol {

    @Published var uiState: GooglePlayAppDetailUiState

    private let storage: PersistentStorable

    init(
        app: GooglePlayAppItem,
        account: AccountModel,
        storage: PersistentStorable? = nil
    ) {
        self.uiState = GooglePlayAppDetailUiState(account: account, app: app)
        self.storage = storage ?? SwiftDataStorable.shared
    }

    func load() async {
        guard uiState.isAppInScope else { return }
        let detailsCache = GooglePlayAppCacheStore<GooglePlayAppDetailsCache>(
            storage: storage,
            accountId: uiState.account.id,
            packageName: uiState.app.packageName
        )
        uiState.defaultLanguage = await detailsCache.load()?.details.defaultLanguage

        guard uiState.canViewReleases else {
            uiState.releaseSections = []
            return
        }
        let summaries = await GooglePlayAppCacheStore<GooglePlayReleaseSummariesCache>(
            storage: storage, accountId: uiState.account.id, packageName: uiState.app.packageName
        ).load()
        let tracks = await GooglePlayAppCacheStore<GooglePlayTracksCache>(
            storage: storage, accountId: uiState.account.id, packageName: uiState.app.packageName
        ).load()
        uiState.releaseSections = GooglePlayAppDetailTrackSection.build(summaries: summaries, tracks: tracks?.tracks)
    }

    func denial(for section: GooglePlayAppDetailSection) -> String? {
        GooglePlayAppSectionAccess.denialMessage(
            account: uiState.account,
            app: uiState.app,
            resource: section.requiredResource
        )
    }

    func presentDenial(_ message: String) {
        uiState.permissionDeniedMessage = message
    }
}
