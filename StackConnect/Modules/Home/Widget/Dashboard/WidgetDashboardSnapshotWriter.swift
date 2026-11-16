import Foundation
import WidgetKit

/// The three Home lists of both stores, as the in-app widgets build them.
struct DashboardLists: Equatable {
    var inReview: [DashboardEntry]
    var awaitingRelease: [DashboardEntry]
    var recentReviews: [DashboardReview]
}

/// Writes the WidgetKit snapshot (plan H6, S6) from the same builders the
/// in-app widgets use, so the home-screen widgets draw the same rows for both
/// stores, then asks WidgetKit to reload.
enum WidgetDashboardSnapshotWriter {

    /// Rows kept per list: more than the large family can draw (6), so the
    /// "+N more" count stays exact through `inReviewCount` / `awaitingReleaseCount`.
    static let maxRows = 12
    static let maxReviews = 5

    /// Loads the three lists exactly like `InReviewWidget`, `AwaitingReleaseWidget`
    /// and `RecentReviewsWidget`.
    static func loadLists(storage: PersistentStorable) async throws -> DashboardLists {
        let accounts = await HomeWidgetDataLoader.loadAccounts(storage: storage)
        let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
        let active = HomeWidgetDataLoader.filterKnownAccounts(allApps.filter { !$0.isArchived }, accountsMap: accounts)
        let phased = await HomeWidgetDataLoader.loadPhasedReleases(for: active, storage: storage)
        let playStatus = await HomeWidgetDataLoader.loadGooglePlaySources(
            storage: storage, accounts: accounts, requiring: .version, includesReleaseCaches: true
        )
        let playReviews = await HomeWidgetDataLoader.loadGooglePlaySources(
            storage: storage, accounts: accounts, requiring: .review, includesReleaseCaches: false
        )
        let reviews: [CustomerReviewModel] = try await storage.fetchAll(CustomerReviewModel.self)
        return DashboardLists(
            inReview: DashboardEntryBuilder.merged(
                appStore: DashboardEntryBuilder.appStoreInReview(active, accounts: accounts),
                googlePlay: DashboardEntryBuilder.googlePlayInReview(playStatus)
            ),
            awaitingRelease: DashboardEntryBuilder.merged(
                appStore: DashboardEntryBuilder.appStoreAwaitingRelease(active, phasedByVersionId: phased, accounts: accounts),
                googlePlay: DashboardEntryBuilder.googlePlayAwaitingRelease(playStatus)
            ),
            recentReviews: DashboardEntryBuilder.reviews(
                reviews, appStoreApps: active, googlePlaySources: playReviews, accounts: accounts, limit: maxReviews
            )
        )
    }

    static func snapshot(from lists: DashboardLists, generatedAt: Date = Date()) -> WidgetDashboardSnapshot {
        WidgetDashboardSnapshot(
            generatedAt: generatedAt,
            inReview: lists.inReview.prefix(maxRows).map(row),
            inReviewCount: lists.inReview.count,
            awaitingRelease: lists.awaitingRelease.prefix(maxRows).map(row),
            awaitingReleaseCount: lists.awaitingRelease.count,
            recentReviews: lists.recentReviews.prefix(maxReviews).map(review)
        )
    }

    static func row(_ entry: DashboardEntry) -> WidgetDashboardRow {
        WidgetDashboardRow(
            id: entry.id,
            name: entry.name,
            iconUrl: entry.iconUrl,
            platform: entry.platform,
            statusText: entry.statusText,
            statusColor: entry.statusColor,
            versionText: entry.versionText,
            progress: entry.progress,
            deepLink: DeepLink.app(accountId: entry.accountId, appId: entry.appId).url.absoluteString
        )
    }

    static func review(_ item: DashboardReview) -> WidgetDashboardReview {
        WidgetDashboardReview(
            id: item.id,
            appName: item.appName,
            iconUrl: item.iconUrl,
            platform: item.platform,
            rating: item.review.rating,
            title: item.review.title,
            body: item.review.body,
            createdDate: item.review.createdDate,
            hasResponse: item.review.hasResponse,
            deepLink: DeepLink.review(accountId: item.accountId, appId: item.appId, reviewId: item.review.id).url.absoluteString
        )
    }

    /// Rebuilds the snapshot, saves it and reloads the widget timelines. A
    /// failure keeps the previous snapshot (logged).
    static func write(storage: PersistentStorable, to url: URL? = WidgetDashboardSnapshotStore.fileURL()) async {
        do {
            let lists = try await loadLists(storage: storage)
            try WidgetDashboardSnapshotStore.save(snapshot(from: lists), to: url)
            Log.print.info("[Widget] Snapshot written: \(lists.inReview.count) in review, \(lists.awaitingRelease.count) awaiting, \(lists.recentReviews.count) reviews")
        } catch {
            Log.print.error("[Widget] Snapshot write failed: \(error.localizedDescription)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
