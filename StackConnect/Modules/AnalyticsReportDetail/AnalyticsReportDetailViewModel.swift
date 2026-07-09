import Foundation

// MARK: - Data Point

/// One aggregated point of the plotted series: a distinct date, its formatted
/// label (per the current granularity), and the summed measure value.
struct AnalyticsDataPoint: Identifiable, Hashable {
    let id: String
    let date: Date
    let label: String
    let value: Double
}

// MARK: - Phase

/// Drives the content area of the detail screen. `loaded` always carries a
/// non-empty series (empty results collapse into `.empty`).
enum AnalyticsDetailPhase: Equatable {
    case loading
    case loaded
    case empty(title: String?, detail: String)
    case needsRequest
    case requested(String)
}

// MARK: - Protocol

@MainActor
protocol AnalyticsReportDetailViewModelProtocol: ObservableObject {
    var uiState: AnalyticsReportDetailUiState { get set }
    func onAppear() async
    func selectGranularity(_ granularity: AnalyticsGranularity) async
    func enableReports() async
    func reactivateReports() async
}

// MARK: - UiState

struct AnalyticsReportDetailUiState {
    let appId: String
    let appName: String
    let report: AnalyticsCatalogReport
    let account: AccountModel

    var granularity: AnalyticsGranularity = .daily
    var phase: AnalyticsDetailPhase = .loading
    var series: [AnalyticsDataPoint] = []

    var isEnabling = false
    var toastMessage: ToastMessage?

    /// True when the resolved ONGOING request has `stoppedDueToInactivity`, i.e.
    /// Apple paused report generation and the displayed data may be stale. Only
    /// the network-resolve path writes it (it's a property of the request, not of
    /// a granularity), so it persists across instant cached-granularity switches.
    var isReportStopped: Bool = false
}

// MARK: - Implementation

@MainActor
final class AnalyticsReportDetailViewModel: AnalyticsReportDetailViewModelProtocol {

    @Published var uiState: AnalyticsReportDetailUiState

    private let keychain: KeyStorable
    private var hasAppeared = false

    /// In-memory caches so toggling back to an already-loaded granularity is
    /// instant (no re-download, no re-parse).
    private var seriesCache: [AnalyticsGranularity: [AnalyticsDataPoint]] = [:]

    private static let maxDownloadBytes: UInt64 = 50 * 1024 * 1024
    private static let pageLimit = 50

    /// Case-insensitive priority list of preferred measure-column headers.
    private static let preferredMeasures = [
        "Counts", "Count", "Value", "Quantity", "Units", "Sessions",
        "Installs", "Installations", "Impressions", "Downloads",
        "Crashes", "Active Devices", "Opt-Ins"
    ]

    init(
        appId: String,
        appName: String,
        report: AnalyticsCatalogReport,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AnalyticsReportDetailUiState(
            appId: appId,
            appName: appName,
            report: report,
            account: account
        )
        self.keychain = keychain
    }

    // MARK: - Lifecycle

    func onAppear() async {
        guard !hasAppeared else { return }
        hasAppeared = true
        await load(.daily)
    }

    func selectGranularity(_ granularity: AnalyticsGranularity) async {
        await load(granularity)
    }

    // MARK: - Load

    private func load(_ granularity: AnalyticsGranularity) async {
        uiState.granularity = granularity

        // Instant path: previously parsed in this session.
        if let cached = seriesCache[granularity] {
            uiState.series = cached
            uiState.phase = cached.isEmpty
                ? .empty(title: nil, detail: String(localized: "This report has no chartable numeric metric."))
                : .loaded
            return
        }

        guard let connection = createConnection() else {
            uiState.phase = .empty(title: nil, detail: String(localized: "Missing credentials for this account."))
            return
        }

        uiState.phase = .loading
        uiState.series = []

        do {
            // 1. Resolve a report request (prefer ONGOING, else the first).
            let requestsPage = try await connection.fetchAnalyticsReportRequestsPage(
                appId: uiState.appId,
                filterAccessType: nil,
                limit: Self.pageLimit,
                pageToken: nil
            )
            guard let request = pickRequest(from: requestsPage.requests) else {
                uiState.phase = .needsRequest
                return
            }
            uiState.isReportStopped = request.stoppedDueToInactivity

            // 2. Find the report whose name matches this catalog entry.
            let reportsPage = try await connection.fetchAnalyticsReportsPage(
                requestId: request.id,
                filterCategory: uiState.report.category.rawValue,
                limit: Self.pageLimit,
                pageToken: nil
            )
            guard let report = matchReport(in: reportsPage.reports) else {
                uiState.phase = .empty(title: nil, detail: String(localized: "This report isn't available yet (Apple may still be generating it)."))
                return
            }

            // 3. Pick the latest instance at this granularity.
            let instancesPage = try await connection.fetchAnalyticsReportInstancesPage(
                reportId: report.id,
                filterGranularity: granularity.rawValue,
                limit: Self.pageLimit,
                pageToken: nil
            )
            guard let instance = latestInstance(in: instancesPage.instances) else {
                uiState.phase = .empty(title: nil, detail: String(localized: "No data at this granularity yet."))
                return
            }

            // 4. Persistent, per-instance file: dedup the segment GET. Analytics
            //    instances are immutable, so once an instance is on disk it never
            //    needs re-downloading — reuse it, otherwise download exactly once.
            let fileURL = self.fileURL(for: granularity, instance: instance)
            let instanceKey = AnalyticsReportFileStore.instanceKey(for: instance)
            let content: AnalyticsReportContent
            if FileManager.default.fileExists(atPath: fileURL.path) {
                content = try parseFile(at: fileURL)
                Log.print.info("[AnalyticsDetail] Reusing on-disk \(granularity.rawValue) file for instance \(instanceKey) (no download)")
            } else {
                Log.print.info("[AnalyticsDetail] No on-disk \(granularity.rawValue) file for instance \(instanceKey) — downloading")
                let segmentsPage = try await connection.fetchAnalyticsReportSegmentsPage(
                    instanceId: instance.id,
                    limit: 1,
                    pageToken: nil
                )
                guard let segment = segmentsPage.segments.first else {
                    uiState.phase = .empty(title: nil, detail: String(localized: "No data at this granularity yet."))
                    return
                }
                let downloaded = try await connection.downloadAnalyticsSegment(
                    url: segment.url,
                    maxBytes: Self.maxDownloadBytes
                )
                try writeCSV(downloaded, to: fileURL)
                content = downloaded
                Log.print.info("[AnalyticsDetail] Downloaded \(granularity.rawValue) instance \(instanceKey): \(downloaded.rowCount) rows")
            }

            // 5. Parse into a plottable series.
            let series = Self.buildSeries(from: content, granularity: granularity)
            seriesCache[granularity] = series
            uiState.series = series
            uiState.phase = series.isEmpty
                ? .empty(title: nil, detail: String(localized: "This report has no chartable numeric metric."))
                : .loaded
        } catch {
            Log.print.error("[AnalyticsDetail] Load failed for \(granularity.rawValue): \(error.localizedDescription)")
            let f = AppleAPIErrorTranslator.friendly(for: error)
            uiState.phase = .empty(title: f.title, detail: f.detail)
        }
    }

    // MARK: - Enable

    func enableReports() async {
        guard uiState.account.canEdit(.analytics) else {
            uiState.toastMessage = ToastMessage(String(localized: "An Admin must enable analytics reports."), icon: "exclamationmark.triangle.fill")
            return
        }
        guard !uiState.isEnabling, let connection = createConnection() else { return }

        uiState.isEnabling = true
        defer { uiState.isEnabling = false }

        do {
            let request = try await connection.createAnalyticsReportRequest(
                appId: uiState.appId,
                accessType: AnalyticsAccessType.ongoing.rawValue
            )
            Log.print.info("[AnalyticsDetail] Created report request \(request.id)")
            uiState.phase = .requested(String(localized: "Requested — Apple generates the data in 24–48 hours."))
        } catch {
            Log.print.error("[AnalyticsDetail] Enable failed: \(error.localizedDescription)")
            uiState.toastMessage = ToastMessage(AppleAPIErrorTranslator.friendlyMessage(for: error), icon: "exclamationmark.triangle.fill")
        }
    }

    // MARK: - Reactivate

    /// Resumes a report request that Apple paused due to inactivity by POSTing a
    /// fresh ONGOING request (Apple stops generating new instances for a stopped
    /// one — the only way to resume is a new request). Mirrors `enableReports()`.
    func reactivateReports() async {
        guard uiState.account.canEdit(.analytics) else {
            uiState.toastMessage = ToastMessage(String(localized: "An Admin must reactivate analytics reports."), icon: "exclamationmark.triangle.fill")
            return
        }
        guard !uiState.isEnabling, let connection = createConnection() else { return }

        uiState.isEnabling = true
        defer { uiState.isEnabling = false }

        do {
            let request = try await connection.createAnalyticsReportRequest(
                appId: uiState.appId,
                accessType: AnalyticsAccessType.ongoing.rawValue
            )
            Log.print.info("[AnalyticsDetail] Reactivated report request \(request.id)")
            uiState.isReportStopped = false
            uiState.phase = .requested(String(localized: "Reactivated — Apple generates fresh data in 24–48 hours."))
        } catch {
            Log.print.error("[AnalyticsDetail] Reactivate failed: \(error.localizedDescription)")
            uiState.toastMessage = ToastMessage(AppleAPIErrorTranslator.friendlyMessage(for: error), icon: "exclamationmark.triangle.fill")
        }
    }

    // MARK: - Resolution helpers

    /// Prefers a non-stopped `ONGOING` request (continuously updated), then any
    /// `ONGOING` (even one paused due to inactivity), then the first. This lets a
    /// freshly-created request win over an old stopped one after reactivation.
    private func pickRequest(from requests: [AnalyticsReportRequestModel]) -> AnalyticsReportRequestModel? {
        requests.first { $0.accessType == AnalyticsAccessType.ongoing.rawValue && !$0.stoppedDueToInactivity }
            ?? requests.first { $0.accessType == AnalyticsAccessType.ongoing.rawValue }
            ?? requests.first
    }

    /// Matches this catalog entry against the live report names using normalized
    /// comparison: lowercase + alphanumerics only, then equality or containment.
    private func matchReport(in reports: [AnalyticsReportModel]) -> AnalyticsReportModel? {
        let target = Self.normalize(uiState.report.apiName)
        guard !target.isEmpty else { return nil }
        return reports.first { report in
            let candidate = Self.normalize(report.name)
            guard !candidate.isEmpty else { return false }
            if candidate == target { return true }
            return candidate.contains(target) || target.contains(candidate)
        }
    }

    /// The newest instance by `processingDate` (ISO `yyyy-MM-dd`, lexicographic).
    private func latestInstance(in instances: [AnalyticsReportInstanceModel]) -> AnalyticsReportInstanceModel? {
        instances.max { ($0.processingDate ?? "") < ($1.processingDate ?? "") }
    }

    // MARK: - File cache

    /// The persistent, per-instance CSV path for a granularity:
    /// `<AppSupport>/AnalyticsReports/<category>/<sanitized apiName>/<GRANULARITY>/<key>.csv`.
    /// Resolved through `AnalyticsReportFileStore` so the detail and Files screens
    /// share one scheme.
    private func fileURL(for granularity: AnalyticsGranularity, instance: AnalyticsReportInstanceModel) -> URL {
        AnalyticsReportFileStore.fileURL(
            category: uiState.report.category,
            apiName: uiState.report.apiName,
            granularity: granularity,
            instance: instance
        )
    }

    /// Lowercases and keeps only alphanumerics, for tolerant report-name matching
    /// (e.g. "App Store Pre-orders" -> "appstorepreorders").
    private static func normalize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.lowercased().unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func writeCSV(_ content: AnalyticsReportContent, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let csv = Self.csv(from: content)
        try csv.data(using: .utf8)?.write(to: url, options: .atomic)
        Log.print.info("[AnalyticsDetail] Saved report file to \(url.path)")
    }

    private func parseFile(at url: URL) throws -> AnalyticsReportContent {
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = Self.parseCSV(text)
        return AnalyticsReportContent(headers: parsed.headers, rows: parsed.rows, rowCount: parsed.rows.count)
    }

    // MARK: - Connection

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}

// MARK: - CSV (round-trip)

extension AnalyticsReportDetailViewModel {

    /// Builds RFC-4180-style CSV from parsed content, quoting any field with a
    /// comma, quote, or newline. (Copied from the retired reports-list VM.)
    static func csv(from content: AnalyticsReportContent) -> String {
        var lines: [String] = []
        lines.append(content.headers.map(escapeCSV).joined(separator: ","))
        for row in content.rows {
            lines.append(row.map(escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func escapeCSV(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Minimal RFC-4180 parser (handles quoted fields, escaped quotes, CRLF) so a
    /// cached CSV can be read back into headers + rows.
    static func parseCSV(_ text: String) -> (headers: [String], rows: [[String]]) {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var index = 0

        while index < chars.count {
            let char = chars[index]
            if inQuotes {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    record.append(field)
                    field = ""
                case "\n":
                    record.append(field)
                    field = ""
                    records.append(record)
                    record = []
                case "\r":
                    break // CRLF: newline handled by the following "\n"
                default:
                    field.append(char)
                }
            }
            index += 1
        }

        // Flush a trailing field/record (file without a final newline).
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }

        guard let headers = records.first else { return ([], []) }
        return (headers, Array(records.dropFirst()))
    }
}

// MARK: - Series building

extension AnalyticsReportDetailViewModel {

    /// Turns generic tabular content into a date-sorted, aggregated series.
    /// Returns an empty array when there is no numeric column to chart.
    static func buildSeries(from content: AnalyticsReportContent, granularity: AnalyticsGranularity) -> [AnalyticsDataPoint] {
        let headers = content.headers
        guard !headers.isEmpty else { return [] }

        // Date column: first header containing "date", else the first column.
        let dateIndex = headers.firstIndex { $0.lowercased().contains("date") } ?? 0

        // Measure column: preferred header, else last all-numeric column.
        guard let measureIndex = measureColumnIndex(headers: headers, rows: content.rows) else {
            return []
        }

        // Aggregate the measure per distinct raw date, preserving first-seen order.
        var sums: [String: Double] = [:]
        var order: [String] = []
        for row in content.rows {
            guard dateIndex < row.count, measureIndex < row.count else { continue }
            guard let value = parseNumber(row[measureIndex]) else { continue }
            let rawDate = row[dateIndex].trimmingCharacters(in: .whitespaces)
            if sums[rawDate] == nil { order.append(rawDate) }
            sums[rawDate, default: 0] += value
        }
        guard !sums.isEmpty else { return [] }

        let parser = posixDateFormatter()
        var parsed: [(raw: String, date: Date?, value: Double)] = order.map { raw in
            (raw, parser.date(from: raw), sums[raw] ?? 0)
        }

        // Sort ascending by date only when every value parsed; otherwise keep the
        // report's own row order (raw label + running index for the x-axis).
        if parsed.allSatisfy({ $0.date != nil }) {
            parsed.sort { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        }

        return parsed.enumerated().map { offset, item in
            let label: String
            if let date = item.date {
                label = displayLabel(for: date, granularity: granularity)
            } else {
                label = item.raw
            }
            return AnalyticsDataPoint(
                id: "\(offset)-\(item.raw)",
                date: item.date ?? .distantPast,
                label: label,
                value: item.value
            )
        }
    }

    static func measureColumnIndex(headers: [String], rows: [[String]]) -> Int? {
        let lowerHeaders = headers.map { $0.lowercased() }
        for preferred in preferredMeasures {
            if let index = lowerHeaders.firstIndex(of: preferred.lowercased()) {
                return index
            }
        }
        guard !rows.isEmpty else { return nil }
        for index in stride(from: headers.count - 1, through: 0, by: -1) {
            let allNumeric = rows.allSatisfy { row in
                index < row.count && parseNumber(row[index]) != nil
            }
            if allNumeric { return index }
        }
        return nil
    }

    /// Parses a numeric cell after stripping thousands separators (commas/spaces).
    static func parseNumber(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    /// POSIX `yyyy-MM-dd` parser (UTC) for the raw ASC date column.
    static func posixDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// Formats a parsed date for display, matching the shape per granularity:
    /// Monthly -> "June, 2025"; Weekly/Daily -> "Jun 30, 2025".
    static func displayLabel(for date: Date, granularity: AnalyticsGranularity) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "UTC")
        switch granularity {
        case .monthly: formatter.dateFormat = "MMMM, yyyy"
        case .weekly:  formatter.dateFormat = "MMM d, yyyy"
        case .daily:   formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }
}
