import Foundation
import StackCoreRust

// MARK: - Quota errors

/// A Google Play API quota or rate limit hit by one request.
struct GooglePlayQuotaHit: Equatable, Sendable {
    /// The core's whole message (Google's text first).
    let message: String
    /// Google's `Retry-After`, when it sent one.
    let retryAfter: TimeInterval?
}

/// Reads the core's quota errors. The core reports every Google quota or rate
/// limit as `StackError.Http` 429, whatever Google answered (a 429, or a 403
/// such as "Listing releases quota exceeded."), with a message shaped
/// `<Google's message> [<STATUS>]; this is a Google Play API quota/rate limit,
/// not a permission problem — wait and retry later[ (Retry-After: N s)]
/// (HTTP <status> on <METHOD> <path>)`.
enum GooglePlayQuota {

    /// What the core appends after Google's own text.
    private static let explanationMarker = "; this is a Google Play API quota/rate limit"

    /// True for a quota or rate limit (`StackError.Http` 429).
    static func isQuotaExceeded(_ error: Error) -> Bool {
        guard case .Http(let status, _)? = error as? StackError else { return false }
        return status == 429
    }

    /// The hit `error` describes, `nil` when it isn't a quota error.
    static func hit(from error: Error) -> GooglePlayQuotaHit? {
        guard case .Http(429, let message)? = error as? StackError else { return nil }
        return GooglePlayQuotaHit(message: message, retryAfter: retryAfter(in: message))
    }

    /// The `Retry-After` seconds the core names ("(Retry-After: 60 s)"), `nil`
    /// when it names none.
    static func retryAfter(in message: String) -> TimeInterval? {
        guard let regex = try? NSRegularExpression(pattern: #"Retry-After:\s*(\d+)\s*s\b"#),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message),
              let seconds = Int(message[range]) else { return nil }
        return TimeInterval(seconds)
    }

    /// Google's own part of the core's message ("Listing releases quota
    /// exceeded. [PERMISSION_DENIED]"), without the core's explanation and
    /// request suffix. Any other text is returned trimmed, as is.
    static func googleMessage(in message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: explanationMarker) else { return trimmed }
        return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Cooldown

/// A per-account pause of the automatic release-summary refreshes after Google
/// answered with a quota or rate limit (`googleplay-quota.{accountId}`).
/// Removed by `AccountCascadeDeleter` with the account.
struct GooglePlayQuotaCooldown: Codable, Hashable, Sendable {
    let accountId: String
    /// No automatic refresh before this date.
    var until: Date
    /// When the quota was hit.
    var recordedAt: Date
    /// The core's message of the hit, for the log and a future report.
    var message: String?

    static func storageId(accountId: String) -> String {
        "googleplay-quota.\(accountId)"
    }

    func isActive(at date: Date) -> Bool {
        until > date
    }
}

// MARK: - Refresher

/// Refreshes the release summaries (`tracks.releases.list`, edit-free) of a
/// Play account's apps while staying under Google's per-minute quota. Shared by
/// the Play app list (`GooglePlayAppListViewModel`) and the background sync leg
/// (`GooglePlayAccountSync`).
///
/// - **Stop at the first quota hit**: no other request of the run is started
///   and the ones in flight are cancelled; every app not fully answered keeps
///   its cached status.
/// - **Cooldown**: the hit pauses automatic refreshes of the account until
///   now + max(`Retry-After`, `minimumCooldown`), persisted as
///   `GooglePlayQuotaCooldown`. While it lasts, an automatic run (list load,
///   Home sync) asks nothing; a pull to refresh tries once, one request first,
///   and a new hit extends the cooldown. A run whose requests answer ends it.
/// - **Minimum interval**: an automatic run skips apps whose summaries were
///   fetched less than `minimumAutomaticInterval` ago.
/// - **Fewer tracks**: an automatic run asks only the tracks known to have a
///   release (tracks cache, previous summaries); every standard track (plus
///   the custom ones of the tracks cache) when nothing is known, on a pull to
///   refresh, and at least every `fullTrackDiscoveryInterval`, so a release on
///   a track that had none is still found.
/// - **Concurrency**: at most `maxConcurrentFetches` requests at once.
///
/// Returns the fresh entries; the callers persist them (the sync leg compares
/// them with the previous entries first).
struct GooglePlayReleaseSummariesRefresher: Sendable {

    enum Trigger: Sendable {
        /// Screen load, Home / background sync.
        case automatic
        /// An explicit pull to refresh.
        case userRefresh
    }

    /// Shortest pause after a quota hit (Google counts most quotas per minute;
    /// this leaves room for every other request of the account).
    static let minimumCooldown: TimeInterval = 15 * 60
    /// An app's summaries are refreshed automatically at most this often.
    static let minimumAutomaticInterval: TimeInterval = 10 * 60
    /// Every standard track is asked again at least this often.
    static let fullTrackDiscoveryInterval: TimeInterval = 24 * 60 * 60
    /// Requests in flight at once.
    static let maxConcurrentFetches = 2

    struct Outcome: Sendable {
        /// Fresh cache entries of the apps whose every track answered.
        var entries: [String: GooglePlayReleaseSummariesCache] = [:]
        /// The cooldown in force after the run, `nil` when none.
        var cooldown: GooglePlayQuotaCooldown?
        /// Nothing was asked: an automatic run during a cooldown.
        var skippedForCooldown = false
        /// Apps skipped because they were refreshed recently.
        var skippedAsRecent: [String] = []
        /// Requests started.
        var requestCount = 0
    }

    let accountId: String
    let storage: PersistentStorable
    let fetcher: any GooglePlayReleaseSummariesFetching
    var maxConcurrent: Int = Self.maxConcurrentFetches
    let logTag: String
    var now: @Sendable () -> Date = { Date() }

    // MARK: - Run

    func refresh(packages: [String], trigger: Trigger) async -> Outcome {
        var outcome = Outcome()
        let current = now()
        let cooldown = await loadCooldown()
        let isCoolingDown = cooldown?.isActive(at: current) ?? false

        if isCoolingDown, trigger == .automatic, let cooldown {
            Log.print.info("[\(logTag, privacy: .public)] Release summaries paused by a Google Play quota until \(cooldown.until.formatted(.iso8601), privacy: .public); \(packages.count, privacy: .public) apps skipped")
            outcome.cooldown = cooldown
            outcome.skippedForCooldown = true
            return outcome
        }

        var plans: [String: TrackPlan] = [:]
        var requests: [(packageName: String, track: String)] = []
        for packageName in packages {
            guard let plan = await trackPlan(packageName: packageName, trigger: trigger, at: current) else {
                outcome.skippedAsRecent.append(packageName)
                continue
            }
            plans[packageName] = plan
            requests += plan.tracks.map { (packageName, $0) }
        }
        if !outcome.skippedAsRecent.isEmpty {
            Log.print.info("[\(logTag, privacy: .public)] Release summaries of \(outcome.skippedAsRecent.count, privacy: .public) apps skipped: refreshed less than \(Int(Self.minimumAutomaticInterval / 60), privacy: .public) min ago")
        }
        guard !requests.isEmpty else {
            outcome.cooldown = isCoolingDown ? cooldown : nil
            if cooldown != nil, !isCoolingDown { await deleteCooldown() }
            return outcome
        }

        let result = await GooglePlayAppListSync.fetchReleaseSummaries(
            requests: requests,
            using: fetcher,
            maxConcurrent: maxConcurrent,
            probeFirst: isCoolingDown,
            logTag: logTag
        )
        outcome.requestCount = result.startedCount

        for (packageName, summaries) in result.summaries {
            guard let plan = plans[packageName] else { continue }
            outcome.entries[packageName] = GooglePlayReleaseSummariesCache(
                accountId: accountId,
                packageName: packageName,
                summaries: summaries,
                fetchedAt: current,
                tracksDiscoveredAt: plan.isFullDiscovery ? current : plan.previousDiscoveredAt
            )
        }

        if let hit = result.quotaHit {
            let wait = max(hit.retryAfter ?? 0, Self.minimumCooldown)
            // A new hit never shortens a cooldown already in force.
            let until = max(current.addingTimeInterval(wait), cooldown?.until ?? .distantPast)
            let updated = GooglePlayQuotaCooldown(accountId: accountId, until: until, recordedAt: current, message: hit.message)
            await saveCooldown(updated)
            outcome.cooldown = updated
            let retryAfter = hit.retryAfter.map { "\(Int($0)) s" } ?? "none"
            Log.print.warning("[\(logTag, privacy: .public)] Google Play quota hit after \(result.startedCount, privacy: .public) of \(requests.count, privacy: .public) release-summary requests (Retry-After: \(retryAfter, privacy: .public)); paused until \(until.formatted(.iso8601), privacy: .public)")
        } else if let cooldown {
            if isCoolingDown && result.answeredCount == 0 {
                // A pull to refresh during the cooldown proved nothing: keep it.
                outcome.cooldown = cooldown
            } else {
                await deleteCooldown()
                Log.print.info("[\(logTag, privacy: .public)] Google Play quota cooldown ended")
            }
        }

        Log.print.info("[\(logTag, privacy: .public)] Release summaries: \(outcome.entries.count, privacy: .public) of \(plans.count, privacy: .public) apps refreshed with \(result.startedCount, privacy: .public) requests (\(trigger == .userRefresh ? "pull to refresh" : "automatic", privacy: .public))")
        return outcome
    }

    // MARK: - Tracks

    /// Which tracks to ask for one app, `nil` to skip it (refreshed recently).
    struct TrackPlan: Equatable, Sendable {
        var tracks: [String]
        /// Every standard track (and every known custom one) is asked.
        var isFullDiscovery: Bool
        var previousDiscoveredAt: Date?
    }

    func trackPlan(packageName: String, trigger: Trigger, at date: Date) async -> TrackPlan? {
        let previous = await GooglePlayAppCacheStore<GooglePlayReleaseSummariesCache>(
            storage: storage, accountId: accountId, packageName: packageName
        ).load()
        if trigger == .automatic, let fetchedAt = previous?.fetchedAt,
           Self.isWithin(Self.minimumAutomaticInterval, from: fetchedAt, to: date) {
            return nil
        }

        let tracksCache = await GooglePlayAppCacheStore<GooglePlayTracksCache>(
            storage: storage, accountId: accountId, packageName: packageName
        ).load()
        let standard = GooglePlayAppListSync.standardTracks
        let custom = (tracksCache?.tracks ?? [])
            .map(\.track)
            .filter { !standard.contains($0.lowercased()) }
        let everyTrack = standard + custom
        let discoveredAt = previous?.tracksDiscoveredAt

        let needsDiscovery = trigger == .userRefresh
            || discoveredAt.map { !Self.isWithin(Self.fullTrackDiscoveryInterval, from: $0, to: date) } ?? true
        if needsDiscovery {
            return TrackPlan(tracks: everyTrack, isFullDiscovery: true, previousDiscoveredAt: discoveredAt)
        }

        // Tracks known to hold a release (what Google lists them with).
        var known = Set((tracksCache?.tracks ?? []).filter { !$0.releases.isEmpty }.map(\.track))
        known.formUnion((previous?.summaries ?? []).map(\.track))
        guard !known.isEmpty else {
            return TrackPlan(tracks: everyTrack, isFullDiscovery: true, previousDiscoveredAt: discoveredAt)
        }
        let ordered = standard.filter { known.contains($0) } + known.filter { !standard.contains($0) }.sorted()
        return TrackPlan(tracks: ordered, isFullDiscovery: false, previousDiscoveredAt: discoveredAt)
    }

    /// `date` is less than `interval` after `start` (a `start` in the future,
    /// e.g. after a clock change, is not "recent").
    private static func isWithin(_ interval: TimeInterval, from start: Date, to date: Date) -> Bool {
        let age = date.timeIntervalSince(start)
        return age >= 0 && age < interval
    }

    // MARK: - Cooldown storage

    func loadCooldown() async -> GooglePlayQuotaCooldown? {
        try? await storage.fetch(GooglePlayQuotaCooldown.self, id: GooglePlayQuotaCooldown.storageId(accountId: accountId))
    }

    private func saveCooldown(_ cooldown: GooglePlayQuotaCooldown) async {
        do {
            try await storage.save(cooldown, id: GooglePlayQuotaCooldown.storageId(accountId: accountId))
        } catch {
            Log.print.error("[\(logTag, privacy: .public)] Saving the quota cooldown failed: \(error.localizedDescription)")
        }
    }

    private func deleteCooldown() async {
        try? await storage.delete(GooglePlayQuotaCooldown.self, id: GooglePlayQuotaCooldown.storageId(accountId: accountId))
    }
}
