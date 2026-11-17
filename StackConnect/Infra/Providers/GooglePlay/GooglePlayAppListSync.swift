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

    /// Tracks a full refresh asks every app for. Custom (closed testing) track
    /// names are only discoverable through an edit, so they are added from the
    /// app's tracks cache once the user has opened Tracks (plan open question
    /// 3). See `GooglePlayReleaseSummariesRefresher.trackPlan`.
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

    /// Result of `fetchReleaseSummaries`.
    struct SummariesResult: Sendable {
        /// Every package whose tracks all answered, with its summaries (possibly
        /// none). Only these may replace their cache entry.
        var summaries: [String: [GooglePlayReleaseSummaryModel]] = [:]
        /// Packages with at least one failed (or never started) request.
        var failed: Set<String> = []
        /// The first quota / rate limit hit, which stopped the run.
        var quotaHit: GooglePlayQuotaHit?
        /// Requests started, and requests that answered.
        var startedCount = 0
        var answeredCount = 0
    }

    /// One `releases.list` request per package and track, at most
    /// `maxConcurrent` in flight. A package is complete only when every one of
    /// its tracks answered.
    ///
    /// The first quota or rate limit (`GooglePlayQuota`) stops the run: no
    /// other request is started and the ones in flight are cancelled, so a
    /// limit Google counts per minute isn't hammered further. Cancellation of
    /// the caller stops scheduling too; unstarted packages are left failed.
    /// With `probeFirst` (a retry while a quota cooldown lasts) one request
    /// runs alone until one answers, then the run widens to `maxConcurrent`.
    static func fetchReleaseSummaries(
        requests: [(packageName: String, track: String)],
        using fetcher: any GooglePlayReleaseSummariesFetching,
        maxConcurrent: Int,
        probeFirst: Bool = false,
        logTag: String
    ) async -> SummariesResult {
        var collected: [String: [GooglePlayReleaseSummaryModel]] = [:]
        var failed = Set<String>()
        var pending = requests[...]
        var quotaHit: GooglePlayQuotaHit?
        var started = 0
        var answered = 0
        let width = max(maxConcurrent, 1)

        enum Outcome: Sendable {
            case answered(packageName: String, summaries: [GooglePlayReleaseSummaryModel])
            case failed(packageName: String)
            case quota(packageName: String, GooglePlayQuotaHit)
        }

        await withTaskGroup(of: Outcome.self) { group in
            var inFlight = 0
            func fill() {
                let limit = probeFirst && answered == 0 ? 1 : width
                while inFlight < limit, quotaHit == nil, !Task.isCancelled, let request = pending.popFirst() {
                    inFlight += 1
                    started += 1
                    group.addTask {
                        do {
                            return .answered(
                                packageName: request.packageName,
                                summaries: try await fetcher.fetchReleaseSummaries(packageName: request.packageName, track: request.track)
                            )
                        } catch {
                            if let hit = GooglePlayQuota.hit(from: error) {
                                return .quota(packageName: request.packageName, hit)
                            }
                            Log.print.info("[\(logTag)] Release summaries failed for \(request.packageName) / \(request.track): \(error.localizedDescription)")
                            return .failed(packageName: request.packageName)
                        }
                    }
                }
            }

            fill()
            for await outcome in group {
                inFlight -= 1
                switch outcome {
                case .answered(let packageName, let summaries):
                    answered += 1
                    collected[packageName, default: []].append(contentsOf: summaries)
                case .failed(let packageName):
                    failed.insert(packageName)
                case .quota(let packageName, let hit):
                    failed.insert(packageName)
                    if quotaHit == nil {
                        quotaHit = hit
                        group.cancelAll()
                    }
                }
                fill()
            }
        }
        failed.formUnion(pending.map(\.packageName))

        var result = SummariesResult(failed: failed, quotaHit: quotaHit, startedCount: started, answeredCount: answered)
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
