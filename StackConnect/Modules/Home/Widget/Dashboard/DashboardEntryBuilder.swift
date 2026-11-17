import Foundation

/// What the dashboard knows about one Google Play app of one account: the
/// cached list item and its release caches.
struct GooglePlayDashboardSource: Hashable {
    let account: AccountModel
    let app: GooglePlayAppItem
    /// `googleplay-releases.*` (edit-free, refreshed by every sync).
    let summaries: GooglePlayReleaseSummariesCache?
    /// `googleplay-tracks.*` (edit-based: as fresh as the last time the user
    /// opened Tracks or changed a rollout in the app).
    let tracks: GooglePlayTracksCache?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.account.id == rhs.account.id && lhs.app == rhs.app
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(account.id)
        hasher.combine(app)
    }
}

/// Builds the provider-neutral dashboard rows (plan S2, H1, H3).
///
/// | Widget | App Store | Google Play |
/// |---|---|---|
/// | In Review | `AppStatusCategorizer.inReviewEntries` | lifecycle `IN_REVIEW`, `NOT_APPROVED`, `NOT_SENT_FOR_REVIEW` |
/// | Awaiting Release | `AppStatusCategorizer.awaitingReleaseEntries`, phased day x of 7 | lifecycle `APPROVED_NOT_PUBLISHED`; staged rollouts (`inProgress` / `halted`) from the tracks cache, with a percentage bar |
enum DashboardEntryBuilder {

    // MARK: - App Store

    static func appStoreInReview(_ apps: [AppModel], accounts: [String: AccountModel]) -> [DashboardEntry] {
        AppStatusCategorizer.inReviewEntries(apps)
            .sorted(by: HomeWidgetDataLoader.sortByRecency)
            .compactMap { appStoreEntry($0, progress: nil, accounts: accounts) }
    }

    static func appStoreAwaitingRelease(
        _ apps: [AppModel],
        phasedByVersionId: [String: PhasedReleaseModel],
        accounts: [String: AccountModel]
    ) -> [DashboardEntry] {
        AppStatusCategorizer.awaitingReleaseEntries(apps, phasedByVersionId: phasedByVersionId)
            .sorted(by: HomeWidgetDataLoader.sortByRecency)
            .compactMap { app in
                var progress: DashboardProgress?
                if let phased = HomeWidgetDataLoader.phasedRelease(for: app, in: phasedByVersionId),
                   phased.state == .active || phased.state == .paused,
                   let day = phased.currentDayNumber {
                    progress = .phased(day: day, total: 7, paused: phased.state == .paused)
                }
                return appStoreEntry(app, progress: progress, accounts: accounts)
            }
    }

    /// `app` is an expanded status entry (one platform version).
    private static func appStoreEntry(
        _ app: AppModel,
        progress: DashboardProgress?,
        accounts: [String: AccountModel]
    ) -> DashboardEntry? {
        guard let state = app.appStoreState else { return nil }
        let id = app.statusEntryID
        return DashboardEntry(
            id: "asc.\(app.accountId).\(id.appId).\(id.platform ?? "-").\(id.versionString ?? "-")",
            provider: .apple,
            accountId: app.accountId,
            appId: app.id,
            name: app.name,
            iconUrl: app.iconUrl,
            platform: DashboardPlatform(raw: app.platform),
            statusText: state.displayName,
            statusColor: DashboardStatusColor(state.color),
            versionText: app.versionString,
            progress: progress,
            recency: app.lastModifiedDate,
            target: .appStore(app),
            account: accounts[app.accountId]
        )
    }

    // MARK: - Google Play

    static let inReviewLifecycles: Set<GooglePlayReleaseLifecycleState> = [.inReview, .notApproved, .notSentForReview]

    /// One row per release waiting on (or refused by) Google's review.
    static func googlePlayInReview(_ sources: [GooglePlayDashboardSource]) -> [DashboardEntry] {
        deduplicated(sources.flatMap { source -> [DashboardEntry] in
            lifecycleReleases(of: source)
                .filter { inReviewLifecycles.contains($0.lifecycleState) }
                .map { googlePlayEntry(source, summary: $0) }
        })
    }

    /// Approved releases waiting for managed publishing, then staged rollouts
    /// from the tracks cache. A cached rollout is dropped when the (fresher)
    /// summaries no longer list that release; without a tracks cache no
    /// rollout row (and no bar) is shown.
    static func googlePlayAwaitingRelease(_ sources: [GooglePlayDashboardSource]) -> [DashboardEntry] {
        deduplicated(sources.flatMap { source -> [DashboardEntry] in
            let approved = lifecycleReleases(of: source)
                .filter { $0.lifecycleState == .approvedNotPublished }
                .map { googlePlayEntry(source, summary: $0) }
            return approved + rolloutEntries(of: source)
        })
    }

    /// Summaries in track display order, newest release first per track.
    private static func lifecycleReleases(of source: GooglePlayDashboardSource) -> [GooglePlayReleaseSummaryModel] {
        source.summaries?.tracks.flatMap(\.releases) ?? []
    }

    private static func googlePlayEntry(_ source: GooglePlayDashboardSource, summary: GooglePlayReleaseSummaryModel) -> DashboardEntry {
        let line = GooglePlayTrackStatusLine(
            track: summary.track,
            lifecycleState: summary.lifecycleState,
            versionName: summary.name == nil ? nil : summary.shortName
        )
        return DashboardEntry(
            id: "play.\(source.account.id).\(source.app.packageName).\(summary.track).\(summary.releaseKey.versionCodes.joined(separator: "-"))",
            provider: .googlePlay,
            accountId: source.account.id,
            appId: source.app.packageName,
            name: source.app.displayName,
            iconUrl: source.app.iconUrl,
            platform: .android,
            statusText: line.text,
            statusColor: DashboardStatusColor(summary.lifecycleState),
            versionText: line.versionName ?? summary.shortName,
            progress: nil,
            recency: nil,
            target: .googlePlay(source.app),
            account: source.account
        )
    }

    private static func rolloutEntries(of source: GooglePlayDashboardSource) -> [DashboardEntry] {
        guard let tracks = source.tracks?.tracks else { return [] }
        let liveKeys = source.summaries.map { Set($0.summaries.map(\.releaseKey)) }
        return GooglePlayTrackModel.sorted(tracks).flatMap { track in
            track.releases.compactMap { release -> DashboardEntry? in
                guard let fraction = release.rolloutFraction else { return nil }
                let key = release.releaseKey(track: track.track)
                if let liveKeys, !liveKeys.contains(key) { return nil }
                let halted = release.status == .halted
                let percent = fraction.formatted(.percent.precision(.fractionLength(0...1)))
                let text = halted
                    ? String(localized: "\(track.kind.displayName) · Halted at \(percent)",
                             comment: "Home Awaiting Release row of a halted Google Play staged rollout: track name, then the rollout percentage.")
                    : String(localized: "\(track.kind.displayName) · Rolling out \(percent)",
                             comment: "Home Awaiting Release row of a Google Play staged rollout: track name, then the rollout percentage.")
                return DashboardEntry(
                    id: "play.\(source.account.id).\(source.app.packageName).\(track.track).\(key.versionCodes.joined(separator: "-")).rollout",
                    provider: .googlePlay,
                    accountId: source.account.id,
                    appId: source.app.packageName,
                    name: source.app.displayName,
                    iconUrl: source.app.iconUrl,
                    platform: .android,
                    statusText: text,
                    statusColor: halted ? .orange : .blue,
                    versionText: release.shortName,
                    progress: .rollout(fraction: fraction, halted: halted, asOf: source.tracks?.fetchedAt),
                    recency: nil,
                    target: .googlePlay(source.app),
                    account: source.account
                )
            }
        }
    }

    /// The same package under two Play accounts is the same release: first wins.
    private static func deduplicated(_ entries: [DashboardEntry]) -> [DashboardEntry] {
        var seen = Set<String>()
        return entries.filter { entry in
            let key = entry.id.replacingOccurrences(of: "play.\(entry.accountId).", with: "")
            return seen.insert(key).inserted
        }
    }

    // MARK: - Mixed stores

    /// App Store rows (by recency) then Google Play rows, so the platform groups
    /// keep each store's order.
    static func merged(appStore: [DashboardEntry], googlePlay: [DashboardEntry]) -> [DashboardEntry] {
        appStore + googlePlay
    }

    /// Groups rows by platform in dashboard order (`DashboardPlatform.sortRank`),
    /// unknown platform last. Order within each group is preserved.
    static func groupByPlatform(_ entries: [DashboardEntry]) -> [(platform: DashboardPlatform?, entries: [DashboardEntry])] {
        var groups: [DashboardPlatform?: [DashboardEntry]] = [:]
        for entry in entries {
            groups[entry.platform, default: []].append(entry)
        }
        var result: [(DashboardPlatform?, [DashboardEntry])] = DashboardPlatform.allCases
            .sorted { $0.sortRank < $1.sortRank }
            .compactMap { platform in
                guard let rows = groups[platform], !rows.isEmpty else { return nil }
                return (platform, rows)
            }
        if let unknown = groups[nil], !unknown.isEmpty {
            result.append((nil, unknown))
        }
        return result
    }

    // MARK: - Reviews

    /// Reviews of known apps of both stores, newest first. A review whose app
    /// (or account) is unknown is dropped (plan H4: no placeholder account).
    /// `appStoreApps` are already narrowed to known accounts and not archived.
    static func reviews(
        _ reviews: [CustomerReviewModel],
        appStoreApps: [AppModel],
        googlePlaySources: [GooglePlayDashboardSource],
        accounts: [String: AccountModel],
        limit: Int? = nil
    ) -> [DashboardReview] {
        let appStoreById = Dictionary(appStoreApps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let playByPackage = Dictionary(googlePlaySources.map { ($0.app.packageName, $0) }, uniquingKeysWith: { first, _ in first })

        let rows = reviews.compactMap { review -> DashboardReview? in
            guard let appId = review.appId else { return nil }
            if let app = appStoreById[appId] {
                // An empty account map means the accounts couldn't be read: keep
                // the row rather than blanking the widget (see `filterKnownAccounts`).
                let account = accounts[app.accountId]
                guard account != nil || accounts.isEmpty else { return nil }
                return DashboardReview(
                    review: review, provider: .apple, accountId: app.accountId, appId: app.id, appName: app.name,
                    iconUrl: app.iconUrl, platform: DashboardPlatform(raw: app.platform),
                    target: .appStore(app), account: account
                )
            }
            if let source = playByPackage[appId] {
                return DashboardReview(
                    review: review, provider: .googlePlay, accountId: source.account.id, appId: appId,
                    appName: source.app.displayName, iconUrl: source.app.iconUrl, platform: .android,
                    target: .googlePlay(source.app), account: source.account
                )
            }
            return nil
        }
        .sorted { ($0.review.createdDate ?? .distantPast) > ($1.review.createdDate ?? .distantPast) }

        guard let limit else { return rows }
        return Array(rows.prefix(limit))
    }
}
