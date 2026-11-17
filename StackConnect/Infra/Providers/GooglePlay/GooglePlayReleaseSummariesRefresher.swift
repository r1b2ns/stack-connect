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

// MARK: - Empty release list

/// `tracks.releases.list` of a track without releases. Google answers it with
/// `204 No Content` (seen on device for empty beta / alpha tracks). The core
/// (stack-connect-core up to fc907e1) only reads a 404 as "no releases": it
/// fails to decode the empty 2xx body and reports
/// `StackError.Decode("tracks.releases.list response: EOF while parsing a value
/// at line 1 column 0")`. Read as an empty list, otherwise every app with an
/// empty track is never cached and every run asks all of its tracks again.
enum GooglePlayEmptyReleaseList {

    private static let responsePrefix = "tracks.releases.list response:"
    private static let emptyBodyMessage = "EOF while parsing a value at line 1 column 0"

    /// True for the core's decode error of an empty `releases.list` body.
    static func isEmptyBody(_ error: Error) -> Bool {
        guard case .Decode(let message)? = error as? StackError else { return false }
        return message.hasPrefix(responsePrefix) && message.contains(emptyBodyMessage)
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
/// (`GooglePlayAccountSync`): both read and write the same cache
/// (`googleplay-releases.*`, saved by the run itself) and go through the same
/// per-account run (`GooglePlayReleaseSummariesRuns`).
///
/// - **One run per account**: a caller arriving while a run of the account is
///   in flight awaits it instead of asking Google again (it shares that run's
///   outcome when the run covers its apps, otherwise it runs after it, and
///   then skips what that run just refreshed).
/// - **Stop at the first quota hit**: no other request of the run is started
///   and the ones in flight are cancelled; every app not fully answered keeps
///   its cached status.
/// - **Cooldown**: the hit pauses automatic refreshes of the account until
///   now + max(`Retry-After`, `minimumCooldown`), persisted as
///   `GooglePlayQuotaCooldown`. While it lasts, an automatic run (list load,
///   Home sync) asks nothing; a pull to refresh tries once, one request first,
///   and a new hit extends the cooldown. A run whose requests answer ends it.
/// - **Minimum interval**: an automatic run skips apps whose summaries were
///   fetched less than `minimumAutomaticInterval` ago, whoever fetched them.
/// - **Fewer tracks**: an automatic run asks only the tracks known to have a
///   release (previous summaries, and the tracks cache when it is newer than
///   the last discovery). Every standard track (plus the custom ones of the
///   tracks cache) is asked when the app was never discovered, on a pull to
///   refresh, and at least every `fullTrackDiscoveryInterval`, so a release on
///   a track that had none is still found. A discovered track without
///   releases is known empty until the next discovery; an app whose every
///   track is empty is not asked at all in between.
/// - **Concurrency**: at most `maxConcurrentFetches` requests at once.
///
/// Saves the fresh entries before returning them, with the entries they
/// replaced (the sync leg compares both for status changes).
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
        /// Fresh cache entries (already saved) of the apps whose every track
        /// answered.
        var entries: [String: GooglePlayReleaseSummariesCache] = [:]
        /// The entries `entries` replaced, for the apps that had one.
        var previousEntries: [String: GooglePlayReleaseSummariesCache] = [:]
        /// The cooldown in force after the run, `nil` when none.
        var cooldown: GooglePlayQuotaCooldown?
        /// Nothing was asked: an automatic run during a cooldown.
        var skippedForCooldown = false
        /// Apps skipped because they were refreshed recently, or because every
        /// track is known empty since the last discovery.
        var skippedAsRecent: [String] = []
        /// Requests started by the run.
        var requestCount = 0
        /// The caller shared a run another caller had already started (its
        /// requests are counted there, not here).
        var sharedInFlightRun = false

        /// This outcome as seen by a caller that joined the run for `packages`.
        func shared(with packages: Set<String>) -> Outcome {
            var outcome = self
            outcome.entries = entries.filter { packages.contains($0.key) }
            outcome.previousEntries = previousEntries.filter { packages.contains($0.key) }
            outcome.skippedAsRecent = skippedAsRecent.filter(packages.contains)
            outcome.requestCount = 0
            outcome.sharedInFlightRun = true
            return outcome
        }
    }

    let accountId: String
    let storage: PersistentStorable
    let fetcher: any GooglePlayReleaseSummariesFetching
    var maxConcurrent: Int = Self.maxConcurrentFetches
    let logTag: String
    var now: @Sendable () -> Date = { Date() }
    /// Where concurrent runs of one account meet. Injected for tests.
    var runs: GooglePlayReleaseSummariesRuns = .shared

    // MARK: - Run

    /// Refreshes `packages`, or shares the run of the account already in
    /// flight (see `GooglePlayReleaseSummariesRuns`).
    func refresh(packages: [String], trigger: Trigger) async -> Outcome {
        let refresher = self
        let outcome = await runs.run(accountId: accountId, packages: packages, trigger: trigger) {
            await refresher.performRefresh(packages: packages, trigger: trigger)
        }
        if outcome.sharedInFlightRun {
            Log.print.info("[\(logTag, privacy: .public)] Release summaries of \(packages.count, privacy: .public) apps shared with the run already in flight (\(outcome.entries.count, privacy: .public) refreshed)")
        }
        return outcome
    }

    private func performRefresh(packages: [String], trigger: Trigger) async -> Outcome {
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
        var previous: [String: GooglePlayReleaseSummariesCache] = [:]
        var requests: [(packageName: String, track: String)] = []
        for packageName in packages {
            let entry = await summariesStore(packageName).load()
            previous[packageName] = entry
            guard let plan = await trackPlan(packageName: packageName, previous: entry, trigger: trigger, at: current) else {
                outcome.skippedAsRecent.append(packageName)
                continue
            }
            plans[packageName] = plan
            requests += plan.tracks.map { (packageName, $0) }
        }
        if !outcome.skippedAsRecent.isEmpty {
            Log.print.info("[\(logTag, privacy: .public)] Release summaries of \(outcome.skippedAsRecent.count, privacy: .public) apps skipped: refreshed less than \(Int(Self.minimumAutomaticInterval / 60), privacy: .public) min ago, or no release on any track")
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

        // Saved here, before the run ends, so whoever awaits or follows it
        // (the other caller, the next screen) reads the fresh entries.
        for (packageName, summaries) in result.summaries {
            guard let plan = plans[packageName] else { continue }
            let entry = GooglePlayReleaseSummariesCache(
                accountId: accountId,
                packageName: packageName,
                summaries: summaries,
                fetchedAt: current,
                tracksDiscoveredAt: plan.isFullDiscovery ? current : plan.previousDiscoveredAt
            )
            await summariesStore(packageName).save(entry)
            outcome.entries[packageName] = entry
            if let replaced = previous[packageName] {
                outcome.previousEntries[packageName] = replaced
            }
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

    /// `previous` is the app's cached summaries entry. `nil` skips the app: an
    /// automatic run within `minimumAutomaticInterval` of the last fetch, or
    /// after a recent discovery that found no release on any track.
    func trackPlan(
        packageName: String,
        previous: GooglePlayReleaseSummariesCache?,
        trigger: Trigger,
        at date: Date
    ) async -> TrackPlan? {
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

        // Tracks known to hold a release: what Google listed at the last
        // discovery or refresh (a track it answered empty is known empty), plus
        // the tracks cache (edit-based) when it was read after that discovery.
        var known = Set((previous?.summaries ?? []).map(\.track))
        if let tracksCache, Self.isNewer(tracksCache.fetchedAt, than: discoveredAt) {
            known.formUnion(tracksCache.tracks.filter { !$0.releases.isEmpty }.map(\.track))
        }
        guard !known.isEmpty else {
            // Discovered recently with no release on any track: nothing to ask
            // until the next discovery (or a pull to refresh).
            return nil
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

    /// `date` is after `reference`; an undated tracks cache counts as newer
    /// only when there is no discovery to compare with.
    private static func isNewer(_ date: Date?, than reference: Date?) -> Bool {
        guard let reference else { return true }
        guard let date else { return false }
        return date > reference
    }

    private func summariesStore(_ packageName: String) -> GooglePlayAppCacheStore<GooglePlayReleaseSummariesCache> {
        GooglePlayAppCacheStore(storage: storage, accountId: accountId, packageName: packageName)
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

// MARK: - One run per account

/// Where the release-summary runs of every Play account meet, so the Home /
/// background sync leg and the Play app list never ask Google for the same
/// tracks at the same time (they used to run back to back, or overlap).
///
/// At most one run per account is in flight. A caller arriving meanwhile:
/// - **shares** it (awaits it and gets its outcome for its own apps) when the
///   run covers every app it wants and is at least as thorough: an automatic
///   caller shares any run, a pull to refresh only another pull to refresh;
/// - otherwise **waits** for it to end, then starts its own run, which skips
///   the apps the previous one has just refreshed (automatic) or asks again
///   (pull to refresh).
///
/// The run itself is an unstructured task: a caller that goes away (the list
/// closed) neither cancels nor loses it, and its entries are saved for the
/// next screen.
actor GooglePlayReleaseSummariesRuns {

    static let shared = GooglePlayReleaseSummariesRuns()

    typealias Outcome = GooglePlayReleaseSummariesRefresher.Outcome
    typealias Trigger = GooglePlayReleaseSummariesRefresher.Trigger

    private struct Run {
        let id: UUID
        let trigger: Trigger
        let packages: Set<String>
        let task: Task<Outcome, Never>

        func covers(_ wanted: Set<String>, for trigger: Trigger) -> Bool {
            packages.isSuperset(of: wanted) && (trigger == .automatic || self.trigger == .userRefresh)
        }
    }

    private var inFlight: [String: Run] = [:]
    /// Callers of each account awaiting a run they didn't start.
    private var waiting: [String: Int] = [:]

    func run(
        accountId: String,
        packages: [String],
        trigger: Trigger,
        operation: @escaping @Sendable () async -> Outcome
    ) async -> Outcome {
        let wanted = Set(packages)
        while let current = inFlight[accountId] {
            waiting[accountId, default: 0] += 1
            let outcome = await current.task.value
            waiting[accountId, default: 1] -= 1
            if current.covers(wanted, for: trigger) {
                return outcome.shared(with: wanted)
            }
            // Not the same work: it has finished (and removed itself); check
            // again, another caller may have started a run meanwhile.
            finish(accountId: accountId, id: current.id)
        }

        let id = UUID()
        let task = Task<Outcome, Never> {
            let outcome = await operation()
            self.finish(accountId: accountId, id: id)
            return outcome
        }
        inFlight[accountId] = Run(id: id, trigger: trigger, packages: wanted, task: task)
        return await task.value
    }

    /// Whether a run of the account is in flight (for tests).
    func isRunning(accountId: String) -> Bool {
        inFlight[accountId] != nil
    }

    /// Callers of the account awaiting a run they didn't start (for tests).
    func waitingCallers(accountId: String) -> Int {
        waiting[accountId] ?? 0
    }

    private func finish(accountId: String, id: UUID) {
        if inFlight[accountId]?.id == id {
            inFlight[accountId] = nil
        }
    }
}
