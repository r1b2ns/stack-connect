import Foundation

/// Shared on-disk layout for downloaded analytics report CSVs.
///
/// Storage is **persistent** (Application Support), **per-app**, **per-instance**,
/// and never auto-deleted. Both the detail screen (which writes/reads the file
/// backing the chart) and the Files screen (which lists/deletes/shares them)
/// resolve their paths through here so the two stay in lock-step.
///
///   `<AppSupport>/AnalyticsReports/<appId>/<category.rawValue>/<sanitized apiName>/<GRANULARITY>/<sanitized appName>-<key>.csv`
///
/// The `<appId>` directory scopes storage per app so two apps that share the
/// same report never mix files or reuse each other's cached CSV. The basename is
/// prefixed with the sanitized app name so a shared single CSV is
/// self-describing (e.g. `MyApp-20250630.csv`); when `sanitize(appName)` is empty
/// the prefix falls back to `appId`. `<key>` is the instance's `processingDate`
/// (stable, human-readable) when present, else its opaque `id`. Because Apple's
/// report instances are immutable, an already-downloaded instance never needs
/// re-downloading — the per-instance path is what lets the detail screen dedup
/// the segment GET.
enum AnalyticsReportFileStore {

    /// `<AppSupport>/AnalyticsReports/<appId>/<category.rawValue>/<sanitized apiName>/`
    static func reportDirectory(appId: String, category: AnalyticsCategory, apiName: String) -> URL {
        baseDirectory()
            .appendingPathComponent(appId, isDirectory: true)
            .appendingPathComponent(category.rawValue, isDirectory: true)
            .appendingPathComponent(sanitize(apiName), isDirectory: true)
    }

    /// The per-instance CSV path for a granularity. The granularity is its own
    /// subdirectory so instances of different granularities never collide. The
    /// basename is prefixed with the app so a shared single CSV is self-describing.
    static func fileURL(
        appId: String,
        appName: String,
        category: AnalyticsCategory,
        apiName: String,
        granularity: AnalyticsGranularity,
        instance: AnalyticsReportInstanceModel
    ) -> URL {
        reportDirectory(appId: appId, category: category, apiName: apiName)
            .appendingPathComponent(granularity.rawValue, isDirectory: true)
            .appendingPathComponent("\(appFilenamePrefix(appName: appName, appId: appId))-\(instanceKey(for: instance)).csv")
    }

    /// The basename prefix that makes a shared CSV self-describing: the sanitized
    /// app name, falling back to the (stable, unique) `appId` when the sanitized
    /// name is empty so the file is never just `-<key>.csv`.
    static func appFilenamePrefix(appName: String, appId: String) -> String {
        let sanitized = sanitize(appName)
        return sanitized.isEmpty ? appId : sanitized
    }

    /// The file key for an instance: its sanitized processing date when present,
    /// else its opaque id.
    static func instanceKey(for instance: AnalyticsReportInstanceModel) -> String {
        if let date = instance.processingDate, !date.isEmpty {
            return sanitize(date)
        }
        return instance.id
    }

    /// Persistent per-app storage root (created on first access). Falls back to
    /// the non-creating lookup only if the creating one throws.
    static func baseDirectory() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AnalyticsReports", isDirectory: true)
    }

    /// Keeps only alphanumerics (e.g. "App Sessions" -> "AppSessions",
    /// "2025-06-30" -> "20250630").
    static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: - Legacy un-scoped cleanup

    /// The legacy top-level directory names — one per `AnalyticsCategory` raw
    /// value. Membership in this set is what marks a top-level entry as a legacy
    /// root (see `purgeLegacyUnscopedFiles(in:)`).
    private static let legacyCategoryDirectoryNames: Set<String> =
        Set(AnalyticsCategory.allCases.map(\.rawValue))

    /// One-time cleanup of report CSVs written under the **legacy un-scoped
    /// layout**, orphaned by the migration to per-app storage.
    ///
    /// Report CSVs used to be stored category-rooted, with no app scoping:
    ///
    ///   `<AppSupport>/AnalyticsReports/<category.rawValue>/<sanitized apiName>/<GRANULARITY>/<key>.csv`
    ///
    /// They now live under a per-app root (`<appId>` comes first). The Files
    /// screen only ever scans `<appId>/…`, so the old category-rooted trees are
    /// invisible and merely waste disk. This deletes them.
    ///
    /// Detection is by **exact** match of a top-level directory name against the
    /// `AnalyticsCategory` raw values (`APP_STORE_ENGAGEMENT`, `COMMERCE`,
    /// `APP_USAGE`, `FRAMEWORK_USAGE`) — all uppercase alphabetic tokens. ASC app
    /// ids are numeric strings, so the current layout never names a *top-level*
    /// entry after a category; a top-level entry whose name is a known category
    /// value is therefore unambiguously a legacy root. This is intentionally not
    /// a heuristic, and it never inspects nested directories (a category folder
    /// living *under* an `<appId>` root is left untouched).
    ///
    /// Best-effort and non-throwing: a missing base directory or a failed removal
    /// is logged, never propagated.
    nonisolated static func purgeLegacyUnscopedFiles() {
        purgeLegacyUnscopedFiles(in: baseDirectory())
    }

    /// Testable overload of `purgeLegacyUnscopedFiles()` operating on an explicit
    /// base directory, so tests can run against a temp dir instead of the real
    /// Application Support.
    nonisolated static func purgeLegacyUnscopedFiles(in base: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            // No base directory yet (nothing was ever downloaded) — tolerate and
            // return quietly; there is nothing to purge.
            return
        }

        for entry in entries where legacyCategoryDirectoryNames.contains(entry.lastPathComponent) {
            let name = entry.lastPathComponent
            do {
                try fm.removeItem(at: entry)
                Log.print.info("[AnalyticsFiles] Purged legacy unscoped directory \(name)")
            } catch {
                Log.print.error("[AnalyticsFiles] Failed to purge legacy unscoped directory \(name): \(error.localizedDescription)")
            }
        }
    }
}
