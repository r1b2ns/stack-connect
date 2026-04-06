import SwiftUI
import AppStoreConnect_Swift_SDK

// MARK: - Protocol

@MainActor
protocol AppAnalyticsViewModelProtocol: ObservableObject {
    var uiState: AppAnalyticsUiState { get set }
    func load() async
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
    var isLoading = false
    var error: String?
    var dateRange: AnalyticsDateRange = .last30Days
    var isFirstTimeSetup = false

    /// Report names discovered from the API (populated by Python enum research):
    /// - APP_STORE_DISCOVERY_AND_ENGAGEMENT_STANDARD → "App Store Discovery And Engagement Standard"
    /// - APP_DOWNLOADS_STANDARD → "App Downloads Standard"
    /// - APP_STORE_INSTALLATION_AND_DELETION_STANDARD → "App Store Installation And Deletion Standard"
    /// - APP_CRASHES → "App Crashes"
    static let metricDefinitions: [AnalyticsMetricDef] = [
        AnalyticsMetricDef(
            id: "first_downloads",
            title: "First-Time Downloads",
            icon: "arrow.down.circle.fill",
            color: .blue,
            category: "APP_STORE_ENGAGEMENT",
            nameHints: ["Downloads", "Discovery", "Engagement"],
            columnCandidates: [
                "First-Time Downloads", "First Time Downloads",
                "first_time_downloads", "first-time_downloads",
                "Total Downloads", "Downloads"
            ],
            isPercentage: false
        ),
        AnalyticsMetricDef(
            id: "redownloads",
            title: "Redownloads",
            icon: "arrow.down.circle",
            color: .cyan,
            category: "APP_STORE_ENGAGEMENT",
            nameHints: ["Downloads", "Discovery", "Engagement"],
            columnCandidates: [
                "Redownloads", "Re-Downloads", "redownloads",
                "re_downloads", "Re Downloads"
            ],
            isPercentage: false
        ),
        AnalyticsMetricDef(
            id: "conversion_rate",
            title: "Conversion Rate",
            icon: "percent",
            color: .green,
            category: "APP_STORE_ENGAGEMENT",
            nameHints: ["Discovery", "Engagement"],
            columnCandidates: [
                "Conversion Rate", "conversion_rate",
                "conversionRate", "Conv. Rate"
            ],
            isPercentage: true
        ),
        AnalyticsMetricDef(
            id: "impressions",
            title: "Impressions",
            icon: "eye.fill",
            color: .purple,
            category: "APP_STORE_ENGAGEMENT",
            nameHints: ["Discovery", "Engagement"],
            columnCandidates: [
                "Impressions", "Total Impressions",
                "impressions", "total_impressions"
            ],
            isPercentage: false
        ),
        AnalyticsMetricDef(
            id: "page_views",
            title: "Product Page Views",
            icon: "doc.text.fill",
            color: .orange,
            category: "APP_STORE_ENGAGEMENT",
            nameHints: ["Discovery", "Engagement"],
            columnCandidates: [
                "Product Page Views", "Total Product Page Views",
                "product_page_views", "Page Views", "page_views"
            ],
            isPercentage: false
        ),
        AnalyticsMetricDef(
            id: "updates",
            title: "Updates",
            icon: "arrow.triangle.2.circlepath",
            color: .indigo,
            category: "APP_USAGE",
            nameHints: ["Installation", "Deletion", "Install"],
            columnCandidates: [
                "Updates", "updates", "App Updates", "app_updates"
            ],
            isPercentage: false
        ),
        AnalyticsMetricDef(
            id: "crashes",
            title: "Crashes",
            icon: "xmark.octagon.fill",
            color: .red,
            category: "APP_USAGE",
            nameHints: ["Crash"],
            columnCandidates: [
                "Crashes", "crashes", "Crash Count",
                "crash_count", "Total Crashes"
            ],
            isPercentage: false
        ),
    ]
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

        // Reset installs/deletes
        uiState.installsDeletes.dataPoints = []
        uiState.installsDeletes.isLoading = true
        uiState.installsDeletes.error = nil

        // Initialize metrics in loading state
        uiState.metrics = AppAnalyticsUiState.metricDefinitions.map {
            AnalyticsMetric(
                id: $0.id,
                title: $0.title,
                icon: $0.icon,
                color: $0.color,
                dataPoints: [],
                isLoading: true,
                isPercentage: $0.isPercentage
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

            // Step 1: Ensure report request exists
            let (requestId, isNew) = try await service.ensureReportRequest()

            // Step 2: Fetch available reports
            let reports = try await service.fetchReports(requestId: requestId)

            // If new request or no reports → first-time setup
            if isNew || reports.isEmpty {
                uiState.isFirstTimeSetup = true
                let message = String(localized: "Analytics reports are being generated. This usually takes 24-48 hours after the first request. Please check back later.")
                uiState.error = message
                markAllMetricsError(message)
                uiState.isLoading = false
                return
            }

            // Step 3: Load installs/deletes/first-time from CSV
            uiState.installsDeletes.isLoading = true
            do {
                let result = try await service.fetchInstallsDeletesData(
                    requestId: requestId,
                    dateRange: uiState.dateRange
                )
                var combined: [AnalyticsSeriesDataPoint] = []
                combined += result.installs.map { AnalyticsSeriesDataPoint(date: $0.date, value: $0.value, series: "Install") }
                combined += result.deletes.map { AnalyticsSeriesDataPoint(date: $0.date, value: $0.value, series: "Delete") }
                uiState.installsDeletes.dataPoints = combined.sorted { $0.date < $1.date }
                uiState.installsDeletes.isLoading = false

                // Populate first-time downloads metric from CSV
                if let idx = uiState.metrics.firstIndex(where: { $0.id == "first_downloads" }) {
                    uiState.metrics[idx].dataPoints = result.firstTimeDownloads
                    uiState.metrics[idx].isLoading = false
                }
            } catch {
                uiState.installsDeletes.isLoading = false
                uiState.installsDeletes.error = error.localizedDescription
                Log.print.error("[Analytics] Installs/Deletes load failed: \(error.localizedDescription)")
            }

            // Step 4: Load remaining metrics concurrently (skip first_downloads — already loaded from CSV)
            let csvMetricIds: Set<String> = ["first_downloads"]
            await withTaskGroup(of: (Int, [AnalyticsDataPoint]?, String?).self) { group in
                for (index, def) in AppAnalyticsUiState.metricDefinitions.enumerated() where !csvMetricIds.contains(def.id) {
                    group.addTask { [dateRange = uiState.dateRange] in
                        do {
                            let points = try await service.fetchMetricData(
                                requestId: requestId,
                                category: def.category,
                                nameHints: def.nameHints,
                                dateRange: dateRange,
                                columnCandidates: def.columnCandidates
                            )
                            return (index, points, nil)
                        } catch {
                            return (index, nil, error.localizedDescription)
                        }
                    }
                }

                for await (index, points, error) in group {
                    uiState.metrics[index].isLoading = false
                    if let points {
                        uiState.metrics[index].dataPoints = points
                    }
                    if let error {
                        uiState.metrics[index].error = error
                    }
                }
            }

            Log.print.info("[Analytics] Finished loading all metrics")
        } catch {
            uiState.error = error.localizedDescription
            markAllMetricsError(error.localizedDescription)
            Log.print.error("[Analytics] Top-level failure: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    // MARK: - Private

    private func markAllMetricsError(_ error: String) {
        for i in uiState.metrics.indices {
            uiState.metrics[i].isLoading = false
            uiState.metrics[i].error = error
        }
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
