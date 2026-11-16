import Foundation
import StackProtocols

/// The edit-free steps that refresh a Google Play account's app list, shared by
/// the Play app list screen (`GooglePlayAppListViewModel`) and the background
/// sync leg (`GooglePlayAccountSync`), so both keep the same cache in step.
///
/// None of these opens a Play edit (plan D14, H2): the app listing comes from
/// the Play Developer Reporting API, icons from the public store page and the
/// release status from `tracks.releases.list`.
enum GooglePlayAppListSync {

    /// Tracks every app is asked for. Custom (closed testing) track names are
    /// only discoverable through an edit, so they are added from the app's
    /// tracks cache once the user has opened Tracks (plan open question 3).
    static let standardTracks = ["production", "beta", "alpha", "internal"]

    // MARK: - Merge

    /// API apps are the source of truth; manually added apps the API doesn't
    /// return are kept. Deduped by package name — when the API starts returning a
    /// manually added app, the API entry (with its display name) wins. The API
    /// has no icons, so each entry keeps the cached icon of the current item with
    /// the same package name. Sorted by display name.
    static func merge(
        remote: [StackProtocols.AppInfo],
        into current: [GooglePlayAppItem]
    ) -> [GooglePlayAppItem] {
        var seen = Set<String>()
        var merged: [GooglePlayAppItem] = []
        var cachedIcons: [String: String] = [:]
        for app in current {
            if let iconUrl = app.iconUrl, cachedIcons[app.packageName] == nil {
                cachedIcons[app.packageName] = iconUrl
            }
        }

        for app in remote where seen.insert(app.bundleId).inserted {
            merged.append(GooglePlayAppItem(
                id: app.bundleId,
                packageName: app.bundleId,
                title: app.name.isEmpty ? nil : app.name,
                isManuallyAdded: false,
                iconUrl: cachedIcons[app.bundleId]
            ))
        }

        for app in current where app.isManuallyAdded && seen.insert(app.packageName).inserted {
            merged.append(app)
        }

        return sorted(merged)
    }

    static func sorted(_ apps: [GooglePlayAppItem]) -> [GooglePlayAppItem] {
        apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Release summaries

    /// The standard tracks, then custom tracks named in the app's tracks cache.
    static func tracksToAsk(
        packageName: String,
        accountId: String,
        storage: PersistentStorable
    ) async -> [String] {
        let tracksCache = GooglePlayAppCacheStore<GooglePlayTracksCache>(
            storage: storage, accountId: accountId, packageName: packageName
        )
        let custom = (await tracksCache.load()?.tracks ?? [])
            .map(\.track)
            .filter { !standardTracks.contains($0.lowercased()) }
        return standardTracks + custom
    }

    /// Result of `fetchReleaseSummaries`.
    struct SummariesResult: Sendable {
        /// Every package whose tracks all answered, with its summaries (possibly
        /// none). Only these may replace their cache entry.
        var summaries: [String: [GooglePlayReleaseSummaryModel]] = [:]
        /// Packages with at least one failed (or never started) request.
        var failed: Set<String> = []
    }

    /// One `releases.list` request per package and track, at most
    /// `maxConcurrent` in flight. A package is complete only when every one of
    /// its tracks answered; cancellation stops scheduling new requests and
    /// leaves the unstarted packages failed.
    static func fetchReleaseSummaries(
        requests: [(packageName: String, track: String)],
        using fetcher: any GooglePlayReleaseSummariesFetching,
        maxConcurrent: Int,
        logTag: String
    ) async -> SummariesResult {
        var collected: [String: [GooglePlayReleaseSummaryModel]] = [:]
        var failed = Set<String>()
        var pending = requests[...]

        typealias Outcome = (packageName: String, summaries: [GooglePlayReleaseSummaryModel]?)
        await withTaskGroup(of: Outcome.self) { group in
            func schedule(_ request: (packageName: String, track: String)) {
                group.addTask {
                    do {
                        return (request.packageName, try await fetcher.fetchReleaseSummaries(packageName: request.packageName, track: request.track))
                    } catch {
                        Log.print.info("[\(logTag)] Release summaries failed for \(request.packageName) / \(request.track): \(error.localizedDescription)")
                        return (request.packageName, nil)
                    }
                }
            }
            for _ in 0..<max(maxConcurrent, 1) {
                guard let request = pending.popFirst() else { break }
                schedule(request)
            }
            for await outcome in group {
                if let fetched = outcome.summaries {
                    collected[outcome.packageName, default: []].append(contentsOf: fetched)
                } else {
                    failed.insert(outcome.packageName)
                }
                if !Task.isCancelled, let request = pending.popFirst() {
                    schedule(request)
                }
            }
        }
        failed.formUnion(pending.map(\.packageName))

        var result = SummariesResult(failed: failed)
        for packageName in Set(requests.map(\.packageName)) where !failed.contains(packageName) {
            result.summaries[packageName] = collected[packageName] ?? []
        }
        return result
    }

    // MARK: - Icons

    /// Looks up the public store icon of every package, at most `maxConcurrent`
    /// at once. Returns the icons found (a `nil` lookup is left out).
    static func fetchIcons(
        packageNames: [String],
        using fetcher: any GooglePlayAppIconFetching,
        maxConcurrent: Int
    ) async -> [String: String] {
        var icons: [String: String] = [:]
        var pending = packageNames[...]
        await withTaskGroup(of: (String, String?).self) { group in
            for _ in 0..<max(maxConcurrent, 1) {
                guard let packageName = pending.popFirst() else { break }
                group.addTask { (packageName, await fetcher.fetchIconUrl(packageName: packageName)) }
            }
            for await (packageName, iconUrl) in group {
                if let iconUrl { icons[packageName] = iconUrl }
                if !Task.isCancelled, let next = pending.popFirst() {
                    group.addTask { (next, await fetcher.fetchIconUrl(packageName: next)) }
                }
            }
        }
        return icons
    }
}
