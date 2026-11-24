import Foundation

// MARK: - Protocol

@MainActor
protocol NetworkAuditViewModelProtocol: ObservableObject {
    var uiState: NetworkAuditUiState { get set }
    func load() async
    func selectSegment(_ segment: NetworkAuditSegment)
    func selectFilter(_ filter: NetworkAuditFilter)
    func updateSearch(_ text: String)
    func copyHost(_ host: String)
    /// The summaries the batch export's "Current filter" scope covers.
    var filteredSummaries: [NetworkAuditEventSummary] { get }
}

// MARK: - UiState

enum NetworkAuditSegment: String, CaseIterable, Identifiable, Sendable {
    case events
    case destinations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .events: return String(localized: "Events", comment: "Network audit: segment listing every event.")
        case .destinations: return String(localized: "Destinations", comment: "Network audit: segment listing every host the app contacted.")
        }
    }
}

enum NetworkAuditFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case apple
    case google
    case telemetry
    case local
    case errors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All", comment: "Network audit filter chip: every event.")
        case .apple: return "Apple"
        case .google: return "Google"
        case .telemetry: return String(localized: "Telemetry", comment: "Network audit filter chip: analytics, crash reports and remote configuration.")
        case .local: return String(localized: "On Device", comment: "Network audit filter chip: events that never left the device.")
        case .errors: return String(localized: "Errors", comment: "Network audit filter chip: failed requests.")
        }
    }

    func matches(_ summary: NetworkAuditEventSummary) -> Bool {
        switch self {
        case .all: return true
        case .apple: return summary.category == .apple
        case .google: return summary.category == .google
        case .telemetry: return summary.category == .telemetry
        case .local: return summary.category == .local
        case .errors: return !summary.isSuccess
        }
    }
}

struct NetworkAuditDayGroup: Identifiable, Equatable {
    let id: Date
    let title: String
    let events: [NetworkAuditEventSummary]
}

struct NetworkAuditDestination: Identifiable, Equatable {
    var id: String { host }
    let host: String
    let category: NetworkAuditCategory
    let requestCount: Int
    let bytesSent: Int64
    let bytesReceived: Int64
    let purpose: String
}

struct NetworkAuditTodaySummary: Equatable {
    var requestCount = 0
    var destinationCount = 0
    var bytesSent: Int64 = 0
    var bytesReceived: Int64 = 0
}

struct NetworkAuditUiState {
    var isLoading = true
    var segment: NetworkAuditSegment = .events
    var filter: NetworkAuditFilter = .all
    var searchText = ""
    var retentionDays = NetworkAuditRetention.default.days
    var today = NetworkAuditTodaySummary()
    var groups: [NetworkAuditDayGroup] = []
    var visibleCount = 0
    var totalCount = 0
    var destinations: [NetworkAuditDestination] = []
    var toast: ToastMessage?
}

// MARK: - Implementation

@MainActor
final class NetworkAuditViewModel: NetworkAuditViewModelProtocol {

    @Published var uiState = NetworkAuditUiState()

    private let dependencies: NetworkAuditDependencies
    private let calendar: Calendar
    private var summaries: [NetworkAuditEventSummary] = []

    init(dependencies: NetworkAuditDependencies? = nil, calendar: Calendar = .current) {
        self.dependencies = dependencies ?? .live
        self.calendar = calendar
    }

    var filteredSummaries: [NetworkAuditEventSummary] {
        let query = uiState.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return summaries.filter { summary in
            guard uiState.filter.matches(summary) else { return false }
            guard !query.isEmpty else { return true }
            return summary.host.lowercased().contains(query)
                || summary.path.lowercased().contains(query)
                || summary.method.lowercased().contains(query)
        }
    }

    func load() async {
        let retention = dependencies.settings.retention
        let now = dependencies.now()
        summaries = await dependencies.store.summaries(since: retention.cutoff(from: now, calendar: calendar))
            .map { $0.withCurrentCategory() }
        uiState.retentionDays = retention.days
        uiState.totalCount = summaries.count
        uiState.today = makeTodaySummary(now: now)
        uiState.destinations = makeDestinations()
        rebuildGroups()
        uiState.isLoading = false
        Log.print.info("[NetworkAudit] Loaded \(self.summaries.count) events")
    }

    func selectSegment(_ segment: NetworkAuditSegment) {
        uiState.segment = segment
    }

    func selectFilter(_ filter: NetworkAuditFilter) {
        uiState.filter = filter
        rebuildGroups()
    }

    func updateSearch(_ text: String) {
        uiState.searchText = text
        rebuildGroups()
    }

    func copyHost(_ host: String) {
        dependencies.pasteboard.copy(host, sensitive: false)
        uiState.toast = ToastMessage(String(localized: "Copied: \(host)", comment: "Network audit toast: something was copied. Argument: what was copied."), icon: "doc.on.doc")
    }

    // MARK: - Private

    private func rebuildGroups() {
        let filtered = filteredSummaries
        uiState.visibleCount = filtered.count
        let byDay = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        uiState.groups = byDay.keys.sorted(by: >).map { day in
            NetworkAuditDayGroup(id: day, title: dayTitle(day), events: byDay[day] ?? [])
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let now = dependencies.now()
        if calendar.isDate(day, inSameDayAs: now) {
            return String(localized: "Today", comment: "Network audit: heading of today's events.")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return String(localized: "Yesterday", comment: "Network audit: heading of yesterday's events.")
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func makeTodaySummary(now: Date) -> NetworkAuditTodaySummary {
        let today = summaries.filter { $0.kind == .http && calendar.isDate($0.date, inSameDayAs: now) }
        return NetworkAuditTodaySummary(
            requestCount: today.count,
            destinationCount: Set(today.map(\.host)).count,
            bytesSent: today.reduce(0) { $0 + $1.bytesSent },
            bytesReceived: today.reduce(0) { $0 + $1.bytesReceived }
        )
    }

    private func makeDestinations() -> [NetworkAuditDestination] {
        let http = summaries.filter { $0.kind == .http }
        return Dictionary(grouping: http, by: \.host).map { host, events in
            let entry = NetworkAuditHostCatalog.entry(host: host, path: events.first?.path ?? "")
            return NetworkAuditDestination(
                host: host,
                category: events.first?.category ?? entry.category,
                requestCount: events.count,
                bytesSent: events.reduce(0) { $0 + $1.bytesSent },
                bytesReceived: events.reduce(0) { $0 + $1.bytesReceived },
                purpose: entry.purpose
            )
        }
        .sorted { lhs, rhs in
            lhs.requestCount == rhs.requestCount ? lhs.host < rhs.host : lhs.requestCount > rhs.requestCount
        }
    }
}
