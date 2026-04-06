import SwiftUI
import AppStoreConnect_Swift_SDK

// MARK: - Protocol

@MainActor
protocol AppAnalyticsViewModelProtocol: ObservableObject {
    var uiState: AppAnalyticsUiState { get set }
    func load() async
    func selectDate(_ date: String?) async
}

// MARK: - Metric Definition

struct AnalyticsMetricDef {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let category: String
    let nameHints: [String]
    let columnCandidates: [String]
    let isPercentage: Bool
}

// MARK: - UiState

struct AppAnalyticsUiState {
    var appId: String
    var account: AccountModel
    var metrics: [AnalyticsMetric] = []
    var installsDeletes = AnalyticsMultiSeriesMetric(
        id: "installs_deletes",
        title: "Installs & Deletes",
        icon: "arrow.down.app.fill",
        dataPoints: [],
        isLoading: true
    )
    var downloads = AnalyticsMultiSeriesMetric(
        id: "downloads",
        title: "Downloads",
        icon: "arrow.down.circle.fill",
        dataPoints: [],
        isLoading: true
    )
    var impressions = AnalyticsMetric(
        id: "impressions",
        title: "Impressions",
        icon: "eye.fill",
        color: .purple,
        dataPoints: [],
        isLoading: true
    )
    var pageViews = AnalyticsMetric(
        id: "page_views",
        title: "Product Page Views",
        icon: "doc.text.fill",
        color: .orange,
        dataPoints: [],
        isLoading: true
    )
    var isLoading = false
    var error: String?
    var isFirstTimeSetup = false

    // Date filter
    var availableDates: [String] = []
    var selectedDate: String? // nil = "All"

    var minDate: String? { availableDates.first }
    var maxDate: String? { availableDates.last }

    // Full data (unfiltered) — used to re-filter without re-downloading
    var fullInstallsDeletes: [AnalyticsSeriesDataPoint] = []
    var fullDownloads: [AnalyticsSeriesDataPoint] = []
    var fullImpressions: [AnalyticsDataPoint] = []
    var fullPageViews: [AnalyticsDataPoint] = []

    static let metricDefinitions: [AnalyticsMetricDef] = []
}

// MARK: - Implementation

@MainActor
final class AppAnalyticsViewModel: AppAnalyticsViewModelProtocol {

    @Published var uiState: AppAnalyticsUiState

    private let keychain: KeyStorable
    private var service: AnalyticsReportService?

    init(
        appId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AppAnalyticsUiState(appId: appId, account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil
        uiState.isFirstTimeSetup = false

        // Reset
        uiState.installsDeletes = AnalyticsMultiSeriesMetric(id: "installs_deletes", title: "Installs & Deletes", icon: "arrow.down.app.fill", dataPoints: [], isLoading: true)
        uiState.downloads = AnalyticsMultiSeriesMetric(id: "downloads", title: "Downloads", icon: "arrow.down.circle.fill", dataPoints: [], isLoading: true)
        uiState.impressions = AnalyticsMetric(id: "impressions", title: "Impressions", icon: "eye.fill", color: .purple, dataPoints: [], isLoading: true)
        uiState.pageViews = AnalyticsMetric(id: "page_views", title: "Product Page Views", icon: "doc.text.fill", color: .orange, dataPoints: [], isLoading: true)
        uiState.selectedDate = nil
        uiState.fullImpressions = []
        uiState.fullPageViews = []

        uiState.metrics = AppAnalyticsUiState.metricDefinitions.map {
            AnalyticsMetric(
                id: $0.id, title: $0.title, icon: $0.icon, color: $0.color,
                dataPoints: [], isLoading: true, isPercentage: $0.isPercentage
            )
        }

        do {
            guard let provider = createProvider() else {
                uiState.error = String(localized: "Failed to create API connection.")
                markAllMetricsError(uiState.error!)
                uiState.isLoading = false
                return
            }

            let service = AnalyticsReportService(provider: provider, appId: uiState.appId)
            self.service = service

            let (requestId, isNew) = try await service.ensureReportRequest()
            let reports = try await service.fetchReports(requestId: requestId)

            if isNew || reports.isEmpty {
                uiState.isFirstTimeSetup = true
                let message = String(localized: "Analytics reports are being generated. This usually takes 24-48 hours after the first request. Please check back later.")
                uiState.error = message
                markAllMetricsError(message)
                uiState.isLoading = false
                return
            }

            // Load CSV-based data concurrently
            var allDates = Set<String>()

            async let installsTask: Void = {
                do {
                    let result = try await service.fetchInstallsDeletesData(requestId: requestId)

                    await MainActor.run {
                        allDates.formUnion(result.availableDates)

                        var installsDeletesSeries: [AnalyticsSeriesDataPoint] = []
                        installsDeletesSeries += result.installs.map { AnalyticsSeriesDataPoint(date: $0.date, value: $0.value, series: "Install") }
                        installsDeletesSeries += result.deletes.map { AnalyticsSeriesDataPoint(date: $0.date, value: $0.value, series: "Delete") }
                        uiState.fullInstallsDeletes = installsDeletesSeries.sorted { $0.date < $1.date }

                        var downloadsSeries: [AnalyticsSeriesDataPoint] = []
                        for (type, points) in result.downloadsByType {
                            downloadsSeries += points.map { AnalyticsSeriesDataPoint(date: $0.date, value: $0.value, series: type) }
                        }
                        uiState.fullDownloads = downloadsSeries.sorted { $0.date < $1.date }
                    }
                } catch {
                    await MainActor.run {
                        uiState.installsDeletes.isLoading = false
                        uiState.installsDeletes.error = error.localizedDescription
                        uiState.downloads.isLoading = false
                        uiState.downloads.error = error.localizedDescription
                    }
                    Log.print.error("[Analytics] Installs/Deletes load failed: \(error.localizedDescription)")
                }
            }()

            async let engagementTask: Void = {
                do {
                    let result = try await service.fetchEngagementData(requestId: requestId)

                    await MainActor.run {
                        allDates.formUnion(result.availableDates)
                        uiState.fullImpressions = result.impressions
                        uiState.fullPageViews = result.pageViews
                    }
                } catch {
                    await MainActor.run {
                        uiState.impressions.isLoading = false
                        uiState.impressions.error = error.localizedDescription
                        uiState.pageViews.isLoading = false
                        uiState.pageViews.error = error.localizedDescription
                    }
                    Log.print.error("[Analytics] Engagement load failed: \(error.localizedDescription)")
                }
            }()

            _ = await (installsTask, engagementTask)

            uiState.availableDates = allDates.sorted()
            applyDateFilter()

            Log.print.info("[Analytics] Finished loading all metrics")
        } catch {
            uiState.error = error.localizedDescription
            markAllMetricsError(error.localizedDescription)
            Log.print.error("[Analytics] Top-level failure: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func selectDate(_ date: String?) async {
        uiState.selectedDate = date
        applyDateFilter()
    }

    // MARK: - Private

    private func applyDateFilter() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        if let selectedDate = uiState.selectedDate {
            guard let targetDate = formatter.date(from: selectedDate) else { return }
            let startOfDay = Calendar.current.startOfDay(for: targetDate)

            uiState.installsDeletes.dataPoints = uiState.fullInstallsDeletes.filter {
                Calendar.current.isDate($0.date, inSameDayAs: startOfDay)
            }
            uiState.downloads.dataPoints = uiState.fullDownloads.filter {
                Calendar.current.isDate($0.date, inSameDayAs: startOfDay)
            }
            uiState.impressions.dataPoints = uiState.fullImpressions.filter {
                Calendar.current.isDate($0.date, inSameDayAs: startOfDay)
            }
            uiState.pageViews.dataPoints = uiState.fullPageViews.filter {
                Calendar.current.isDate($0.date, inSameDayAs: startOfDay)
            }
        } else {
            uiState.installsDeletes.dataPoints = uiState.fullInstallsDeletes
            uiState.downloads.dataPoints = uiState.fullDownloads
            uiState.impressions.dataPoints = uiState.fullImpressions
            uiState.pageViews.dataPoints = uiState.fullPageViews
        }

        uiState.installsDeletes.isLoading = false
        uiState.downloads.isLoading = false
        uiState.impressions.isLoading = false
        uiState.pageViews.isLoading = false
    }

    private func markAllMetricsError(_ error: String) {
        for i in uiState.metrics.indices {
            uiState.metrics[i].isLoading = false
            uiState.metrics[i].error = error
        }
        uiState.installsDeletes.isLoading = false
        uiState.installsDeletes.error = error
        uiState.downloads.isLoading = false
        uiState.downloads.error = error
        uiState.impressions.isLoading = false
        uiState.impressions.error = error
        uiState.pageViews.isLoading = false
        uiState.pageViews.error = error
    }

    private func createProvider() -> APIProvider? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }

        do {
            let config = try APIConfiguration(
                issuerID: credentials.issuerID,
                privateKeyID: credentials.privateKeyID,
                privateKey: credentials.privateKey
            )
            return APIProvider(configuration: config)
        } catch {
            Log.print.error("[Analytics] Provider creation failed: \(error.localizedDescription)")
            return nil
        }
    }
}
