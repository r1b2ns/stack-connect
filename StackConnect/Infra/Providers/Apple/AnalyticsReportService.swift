import Foundation
import Compression
import AppStoreConnect_Swift_SDK

/// Service that handles the multi-step Analytics Reports API workflow.
///
/// Workflow: Create Request → List Reports → List Instances → Get Segments → Download TSV
///
/// Important: After creating an ONGOING request for the first time,
/// Apple takes 24-48 hours to generate the initial reports.
actor AnalyticsReportService {

    nonisolated(unsafe) private let provider: APIProvider
    private let appId: String

    private var cachedReports: [(id: String, name: String, category: String)]?
    private var cachedRequestId: String?

    init(provider: APIProvider, appId: String) {
        self.provider = provider
        self.appId = appId
    }

    // MARK: - Step 1: Report Request

    /// Finds an existing ONGOING report request or creates one.
    /// Returns (requestId, isNewlyCreated).
    func ensureReportRequest() async throws -> (id: String, isNew: Bool) {
        let listEndpoint = APIEndpoint.v1.apps.id(appId).analyticsReportRequests.get(
            parameters: .init(
                filterAccessType: [.ongoing],
                limit: 10
            )
        )

        let listResponse = try await provider.request(listEndpoint)

        // Find an active (not stopped) request
        if let existing = listResponse.data.first(where: { $0.attributes?.isStoppedDueToInactivity != true }) {
            Log.print.info("[Analytics] Found existing report request: \(existing.id)")
            cachedRequestId = existing.id
            return (existing.id, false)
        }

        // Create a new one
        let body = AnalyticsReportRequestCreateRequest(
            data: .init(
                type: .analyticsReportRequests,
                attributes: .init(accessType: .ongoing),
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: appId))
                )
            )
        )

        let createEndpoint = APIEndpoint.v1.analyticsReportRequests.post(body)
        let createResponse = try await provider.request(createEndpoint)
        Log.print.info("[Analytics] Created new ONGOING report request: \(createResponse.data.id)")
        cachedRequestId = createResponse.data.id
        return (createResponse.data.id, true)
    }

    // MARK: - Step 2: List Reports

    /// Fetches all available reports for a request.
    func fetchReports(requestId: String) async throws -> [(id: String, name: String, category: String)] {
        if let cached = cachedReports { return cached }

        let endpoint = APIEndpoint.v1.analyticsReportRequests.id(requestId).reports.get(
            parameters: .init(limit: 200)
        )
        let response = try await provider.request(endpoint)

        let reports = response.data.compactMap { report -> (id: String, name: String, category: String)? in
            guard let name = report.attributes?.name,
                  let category = report.attributes?.category?.rawValue else { return nil }
            return (id: report.id, name: name, category: category)
        }

        cachedReports = reports

        let names = reports.map { "  \($0.name) [\($0.category)]" }.joined(separator: "\n")
        Log.print.info("[Analytics] Available reports (\(reports.count)):\n\(names)")

        return reports
    }

    // MARK: - Step 3: Find Report

    /// Finds a report matching a category and name hints.
    func findReport(
        requestId: String,
        category: String,
        nameHints: [String]
    ) async throws -> (id: String, name: String, category: String)? {
        let reports = try await fetchReports(requestId: requestId)

        // Try by category + name hint
        for hint in nameHints {
            if let match = reports.first(where: {
                $0.category == category &&
                $0.name.localizedCaseInsensitiveContains(hint)
            }) {
                Log.print.info("[Analytics] Matched report: \(match.name) via hint '\(hint)'")
                return match
            }
        }

        // Fallback: first report in category
        if let fallback = reports.first(where: { $0.category == category }) {
            Log.print.info("[Analytics] Fallback report for \(category): \(fallback.name)")
            return fallback
        }

        Log.print.error("[Analytics] No report found for category=\(category) hints=\(nameHints)")
        return nil
    }

    // MARK: - Step 4: List Instances

    /// Fetches available instances for a report (no date filter — fetches all, filters locally).
    func fetchInstances(reportId: String) async throws -> [(id: String, processingDate: String)] {
        let endpoint = APIEndpoint.v1.analyticsReports.id(reportId).instances.get(
            parameters: .init(
                filterGranularity: [.daily],
                limit: 200
            )
        )
        let response = try await provider.request(endpoint)

        let instances = response.data.compactMap { instance -> (id: String, processingDate: String)? in
            guard let date = instance.attributes?.processingDate else { return nil }
            return (id: instance.id, processingDate: date)
        }

        Log.print.info("[Analytics] Found \(instances.count) daily instances for report")
        return instances
    }

    // MARK: - Step 5: Get Segments

    func fetchSegments(instanceId: String) async throws -> [URL] {
        let endpoint = APIEndpoint.v1.analyticsReportInstances.id(instanceId).segments.get(limit: 10)
        let response = try await provider.request(endpoint)
        return response.data.compactMap { $0.attributes?.url }
    }

    // MARK: - Step 6: Download & Parse TSV

    /// Downloads a gzip-compressed TSV file and parses it.
    func downloadAndParseTSV(url: URL) async throws -> (headers: [String], rows: [[String: String]]) {
        let (data, _) = try await URLSession.shared.data(from: url)

        let decompressed: Data
        if data.count > 2 && data[0] == 0x1f && data[1] == 0x8b {
            decompressed = Self.gunzip(data)
        } else {
            decompressed = data
        }

        guard let content = String(data: decompressed, encoding: .utf8) else {
            Log.print.error("[Analytics] Failed to decode TSV as UTF-8")
            return ([], [])
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return ([], []) }

        let headers = headerLine.components(separatedBy: "\t").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var rows: [[String: String]] = []
        for line in lines.dropFirst() {
            let values = line.components(separatedBy: "\t")
            var row: [String: String] = [:]
            for (i, header) in headers.enumerated() where i < values.count {
                row[header] = values[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            rows.append(row)
        }

        return (headers, rows)
    }

    // MARK: - High-Level: Fetch Metric Data

    /// Full pipeline: find report → get instances → download segments → aggregate by date.
    func fetchMetricData(
        requestId: String,
        category: String,
        nameHints: [String],
        dateRange: AnalyticsDateRange,
        columnCandidates: [String]
    ) async throws -> [AnalyticsDataPoint] {

        // Step A: Find report
        guard let report = try await findReport(
            requestId: requestId,
            category: category,
            nameHints: nameHints
        ) else {
            throw AnalyticsError.reportNotFound(category: category)
        }

        // Step B: Fetch all instances (no date filter)
        let allInstances = try await fetchInstances(reportId: report.id)
        guard !allInstances.isEmpty else {
            throw AnalyticsError.noInstances
        }

        // Step C: Filter instances by date range locally
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startStr = formatter.string(from: dateRange.startDate)
        let endStr = formatter.string(from: Date())

        let filteredInstances = allInstances.filter { inst in
            inst.processingDate >= startStr && inst.processingDate <= endStr
        }.sorted { $0.processingDate < $1.processingDate }

        guard !filteredInstances.isEmpty else {
            Log.print.info("[Analytics] No instances in date range \(startStr)...\(endStr)")
            return []
        }

        Log.print.info("[Analytics] Processing \(filteredInstances.count) instances for '\(report.name)' in \(startStr)...\(endStr)")

        // Step D: Download segments and aggregate
        let dateParser = DateFormatter()
        dateParser.dateFormat = "yyyy-MM-dd"

        var aggregated: [String: Double] = [:]
        var headersLogged = false

        for instance in filteredInstances {
            let urls = try await fetchSegments(instanceId: instance.id)
            for url in urls {
                let (headers, rows) = try await downloadAndParseTSV(url: url)

                if !headersLogged && !headers.isEmpty {
                    headersLogged = true
                    Log.print.info("[Analytics] TSV headers for '\(report.name)': \(headers)")
                }

                // Find date column
                guard let dateCol = Self.findColumn(in: headers, matching: ["Date", "date", "Report Date", "report_date"]) else {
                    Log.print.error("[Analytics] No date column in headers: \(headers)")
                    continue
                }

                // Find value column
                guard let valueCol = Self.findColumn(in: headers, matching: columnCandidates) else {
                    Log.print.error("[Analytics] No column matching \(columnCandidates) in headers: \(headers)")
                    throw AnalyticsError.columnNotFound(
                        column: columnCandidates.first ?? "?",
                        available: headers
                    )
                }

                Log.print.info("[Analytics] Using dateCol='\(dateCol)' valueCol='\(valueCol)'")

                for row in rows {
                    if let dateStr = row[dateCol],
                       let valueStr = row[valueCol],
                       let value = Double(valueStr) {
                        aggregated[dateStr, default: 0] += value
                    }
                }
            }
        }

        Log.print.info("[Analytics] Aggregated \(aggregated.count) data points for column candidates \(columnCandidates)")

        return aggregated.compactMap { dateStr, value in
            guard let date = dateParser.date(from: dateStr) else { return nil }
            return AnalyticsDataPoint(date: date, value: value)
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Helpers

    static func findColumn(in headers: [String], matching candidates: [String]) -> String? {
        for candidate in candidates {
            // Exact match (case-insensitive)
            if let match = headers.first(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return match
            }
        }
        // Fallback: contains match
        for candidate in candidates {
            let lower = candidate.lowercased()
            if let match = headers.first(where: { $0.lowercased().contains(lower) }) {
                return match
            }
        }
        // Fallback: underscore-normalized match
        let normalizedHeaders = headers.map { ($0, $0.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")) }
        for candidate in candidates {
            let normalizedCandidate = candidate.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
            if let match = normalizedHeaders.first(where: { $0.1 == normalizedCandidate }) {
                return match.0
            }
        }
        return nil
    }

    // MARK: - Gzip

    private static func gunzip(_ data: Data) -> Data {
        guard data.count > 10 else { return data }

        let strippedData = data.dropFirst(10)
        let sourceSize = strippedData.count
        let bufferSize = max(sourceSize * 10, 1_048_576) // at least 1MB
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        let decodedSize = strippedData.withUnsafeBytes { rawBuffer -> Int in
            guard let sourcePointer = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                sourcePointer,
                sourceSize,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decodedSize > 0 else { return data }
        return Data(bytes: destinationBuffer, count: decodedSize)
    }
}

// MARK: - Errors

enum AnalyticsError: LocalizedError {
    case reportNotFound(category: String)
    case noInstances
    case columnNotFound(column: String, available: [String])
    case reportsNotReady

    var errorDescription: String? {
        switch self {
        case .reportNotFound(let category):
            return String(localized: "No report found for category '\(category)'. Reports may take up to 48 hours to generate.")
        case .noInstances:
            return String(localized: "No data instances available yet. Please check back later.")
        case .columnNotFound(let column, let available):
            return String(localized: "Column '\(column)' not found. Available: \(available.joined(separator: ", "))")
        case .reportsNotReady:
            return String(localized: "Analytics reports are being generated. This usually takes 24-48 hours after the first request. Please check back later.")
        }
    }
}
