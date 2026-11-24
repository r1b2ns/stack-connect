import Foundation

// MARK: - Share item

/// A temporary export file handed to the share sheet, deleted once the share
/// sheet goes away (no copy stays in the app).
struct NetworkAuditShareItem: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL
}

enum NetworkAuditShareFile {
    /// Writes `text` to a protected temporary file named `name`.
    static func write(_ text: String, name: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NetworkAuditExport", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            Log.print.error("[NetworkAudit] Failed to write the export file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func remove(_ item: NetworkAuditShareItem?) {
        guard let item else { return }
        try? FileManager.default.removeItem(at: item.fileURL)
    }
}

// MARK: - Protocol

@MainActor
protocol NetworkAuditExportViewModelProtocol: ObservableObject {
    var uiState: NetworkAuditExportUiState { get set }
    func load() async
    func selectScope(_ scope: NetworkAuditExportScope) async
    func selectFormat(_ format: NetworkAuditBatchFormat) async
    func setIncludeBodies(_ enabled: Bool) async
    func copyPreview()
    func export() async
    func shareDidFinish()
}

// MARK: - UiState

enum NetworkAuditExportScope: String, CaseIterable, Identifiable, Sendable {
    case currentFilter
    case today
    case entireLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentFilter: return String(localized: "Current Filter", comment: "Network audit export scope: the events of the list's filter.")
        case .today: return String(localized: "Today", comment: "Network audit export scope: today's events.")
        case .entireLog: return String(localized: "Entire Log", comment: "Network audit export scope: every stored event.")
        }
    }
}

struct NetworkAuditExportUiState {
    var scope: NetworkAuditExportScope = .currentFilter
    var format: NetworkAuditBatchFormat = .json
    var includeBodies = true
    var counts: [NetworkAuditExportScope: Int] = [:]
    var filterTitle = ""
    var retentionDays = NetworkAuditRetention.default.days
    var preview = ""
    var isExporting = false
    var shareItem: NetworkAuditShareItem?
    var toast: ToastMessage?

    var selectedCount: Int { counts[scope] ?? 0 }
}

// MARK: - Implementation

@MainActor
final class NetworkAuditExportViewModel: NetworkAuditExportViewModelProtocol {

    @Published var uiState = NetworkAuditExportUiState()

    /// Events shown in the preview.
    static let previewLimit = 2

    private let filtered: [NetworkAuditEventSummary]
    private let dependencies: NetworkAuditDependencies
    private let calendar: Calendar
    private var all: [NetworkAuditEventSummary] = []
    private var previewEvents: [NetworkAuditEventSummary: NetworkAuditEvent] = [:]

    init(
        filteredSummaries: [NetworkAuditEventSummary],
        filterTitle: String,
        dependencies: NetworkAuditDependencies? = nil,
        calendar: Calendar = .current
    ) {
        self.filtered = filteredSummaries
        self.dependencies = dependencies ?? .live
        self.calendar = calendar
        uiState.filterTitle = filterTitle
    }

    func load() async {
        let now = dependencies.now()
        let retention = dependencies.settings.retention
        all = await dependencies.store.summaries(since: retention.cutoff(from: now, calendar: calendar))
        uiState.retentionDays = retention.days
        uiState.counts = [
            .currentFilter: filtered.count,
            .today: all.filter { calendar.isDate($0.date, inSameDayAs: now) }.count,
            .entireLog: all.count
        ]
        await refreshPreview()
    }

    func selectScope(_ scope: NetworkAuditExportScope) async {
        uiState.scope = scope
        await refreshPreview()
    }

    func selectFormat(_ format: NetworkAuditBatchFormat) async {
        uiState.format = format
        await refreshPreview()
    }

    func setIncludeBodies(_ enabled: Bool) async {
        uiState.includeBodies = enabled
        await refreshPreview()
    }

    func copyPreview() {
        dependencies.pasteboard.copy(uiState.preview, sensitive: false)
        uiState.toast = ToastMessage(String(localized: "Copied: Preview (masked)", comment: "Network audit toast: the export preview was copied."), icon: "doc.on.doc")
    }

    func export() async {
        uiState.isExporting = true
        defer { uiState.isExporting = false }
        let summaries = summaries(for: uiState.scope)
        let events = await dependencies.store.events(for: summaries).map { [dependencies] in $0.sanitizedForDisplay(identity: dependencies.appIdentity) }
        let text = dependencies.exporter.batch(events, format: uiState.format, includeBodies: includeBodies)
        let name = "StackConnect-Audit-\(Self.fileStamp(dependencies.now())).\(uiState.format.fileExtension)"
        guard let url = NetworkAuditShareFile.write(text, name: name) else {
            uiState.toast = ToastMessage(String(localized: "The export couldn't be prepared.", comment: "Network audit toast: writing the export file failed."), icon: "exclamationmark.triangle.fill")
            return
        }
        uiState.shareItem = NetworkAuditShareItem(fileURL: url)
        dependencies.localRecorder?.recordExport(NetworkAuditExportRecord(
            formatName: uiState.format.title,
            subject: String(localized: "\(events.count) events · \(uiState.scope.title)", comment: "Network audit: subject of a batch export event. Arguments: event count, scope."),
            action: .shared,
            includesRealToken: false,
            byteCount: Int64(text.utf8.count)
        ))
    }

    func shareDidFinish() {
        NetworkAuditShareFile.remove(uiState.shareItem)
        uiState.shareItem = nil
    }

    // MARK: - Private

    private var includeBodies: Bool {
        uiState.includeBodies && uiState.format.supportsBodies
    }

    private func summaries(for scope: NetworkAuditExportScope) -> [NetworkAuditEventSummary] {
        switch scope {
        case .currentFilter: return filtered
        case .today: return all.filter { calendar.isDate($0.date, inSameDayAs: dependencies.now()) }
        case .entireLog: return all
        }
    }

    private func refreshPreview() async {
        let head = Array(summaries(for: uiState.scope).prefix(Self.previewLimit))
        var events: [NetworkAuditEvent] = []
        for summary in head {
            if let cached = previewEvents[summary] {
                events.append(cached)
            } else if let event = await dependencies.store.event(for: summary)?.sanitizedForDisplay(identity: dependencies.appIdentity) {
                previewEvents[summary] = event
                events.append(event)
            }
        }
        uiState.preview = dependencies.exporter.batch(events, format: uiState.format, includeBodies: includeBodies)
    }

    static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
