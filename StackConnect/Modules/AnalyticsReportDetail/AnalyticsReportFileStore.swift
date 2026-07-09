import Foundation

/// Shared on-disk layout for downloaded analytics report CSVs.
///
/// Storage is **persistent** (Application Support), **per-instance**, and never
/// auto-deleted. Both the detail screen (which writes/reads the file backing the
/// chart) and the Files screen (which lists/deletes/shares them) resolve their
/// paths through here so the two stay in lock-step.
///
///   `<AppSupport>/AnalyticsReports/<category.rawValue>/<sanitized apiName>/<GRANULARITY>/<key>.csv`
///
/// where `<key>` is the instance's `processingDate` (stable, human-readable)
/// when present, else its opaque `id`. Because Apple's report instances are
/// immutable, an already-downloaded instance never needs re-downloading — the
/// per-instance path is what lets the detail screen dedup the segment GET.
enum AnalyticsReportFileStore {

    /// `<AppSupport>/AnalyticsReports/<category.rawValue>/<sanitized apiName>/`
    static func reportDirectory(category: AnalyticsCategory, apiName: String) -> URL {
        baseDirectory()
            .appendingPathComponent(category.rawValue, isDirectory: true)
            .appendingPathComponent(sanitize(apiName), isDirectory: true)
    }

    /// The per-instance CSV path for a granularity. The granularity is its own
    /// subdirectory so instances of different granularities never collide.
    static func fileURL(
        category: AnalyticsCategory,
        apiName: String,
        granularity: AnalyticsGranularity,
        instance: AnalyticsReportInstanceModel
    ) -> URL {
        reportDirectory(category: category, apiName: apiName)
            .appendingPathComponent(granularity.rawValue, isDirectory: true)
            .appendingPathComponent("\(instanceKey(for: instance)).csv")
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
}
