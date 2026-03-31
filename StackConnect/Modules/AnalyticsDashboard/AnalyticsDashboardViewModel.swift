import Foundation
import APIProviderFirebase

// MARK: - Protocol

@MainActor
protocol AnalyticsDashboardViewModelProtocol: ObservableObject {
    var uiState: AnalyticsDashboardUiState { get set }
    func load() async
}

// MARK: - Chart Data Models

enum ActiveUsersSeries: String, CaseIterable, Identifiable {
    case dau = "Daily"
    case wau = "7-day"
    case mau = "28-day"

    var id: String { rawValue }
}

struct ActiveUsersPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Int
    let series: ActiveUsersSeries
}

// MARK: - UiState

struct AnalyticsDashboardUiState {
    var project: FirebaseProjectModel
    var account: AccountModel
    var isLoading = false
    var error: String?

    /// When the Analytics Data API is disabled, this contains the activation URL.
    var apiActivationURL: String?

    /// Points for the "User activity over time" chart
    var chartPoints: [ActiveUsersPoint] = []

    /// Latest summary values
    var currentDAU: Int = 0
    var currentWAU: Int = 0
    var currentMAU: Int = 0

    /// The linked GA4 property ID (numeric string)
    var propertyId: String?
    var propertyDisplayName: String?
}

// MARK: - Implementation

@MainActor
final class AnalyticsDashboardViewModel: AnalyticsDashboardViewModelProtocol {

    @Published var uiState: AnalyticsDashboardUiState

    private let keychain: KeyStorable

    init(
        project: FirebaseProjectModel,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AnalyticsDashboardUiState(project: project, account: account)
        self.keychain = keychain
    }

    // MARK: - Load

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        guard let provider = createProvider() else {
            uiState.error = String(localized: "No credentials found for this account.")
            uiState.isLoading = false
            return
        }

        do {
            // Step 1: fetch the linked Analytics property ID
            let details = try await provider.request(
                FirebaseAPI.v1beta1.projects.id(uiState.project.projectId).analyticsDetails()
            )

            guard let propertyId = details.analyticsProperty?.id, !propertyId.isEmpty else {
                uiState.error = String(localized: "No Google Analytics property linked to this project.")
                uiState.isLoading = false
                return
            }

            uiState.propertyId = propertyId
            uiState.propertyDisplayName = details.analyticsProperty?.displayName

            // Step 2: run the report – daily active users (+ 7d and 28d rolling) for last 30 days
            let report = try await provider.request(
                FirebaseAPI.analyticsData(propertyId: propertyId).runReport(
                    RunReportRequest(
                        dimensions: [.init(name: "date")],
                        metrics: [
                            .init(name: "activeUsers"),
                            .init(name: "active7DayUsers"),
                            .init(name: "active28DayUsers")
                        ],
                        dateRanges: [.init(startDate: "30daysAgo", endDate: "today")],
                        orderBys: [.init(dimension: .init(dimensionName: "date"), desc: false)],
                        keepEmptyRows: true
                    )
                )
            )

            processReport(report)
            Log.print.info("[Analytics] Loaded report for property \(propertyId)")
        } catch let apiError as APIProviderFirebase.Error {
            handleAPIError(apiError)
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[Analytics] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    // MARK: - Error Handling

    private func handleAPIError(_ apiError: APIProviderFirebase.Error) {
        switch apiError {
        case .requestFailure(_, let errorResponse, _):
            if let errorResponse, errorResponse.isServiceDisabled {
                uiState.apiActivationURL = errorResponse.activationURL
                uiState.error = String(localized: "The Google Analytics Data API is not enabled for this project. Enable it in the Google Cloud Console to view analytics.")
            } else {
                uiState.error = apiError.localizedDescription
            }
        default:
            uiState.error = apiError.localizedDescription
        }
        Log.print.error("[Analytics] API error: \(apiError.localizedDescription)")
    }

    // MARK: - Private

    private func processReport(_ report: RunReportResponse) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        var points: [ActiveUsersPoint] = []

        for row in report.rows ?? [] {
            guard let dateStr = row.dimensionValues?.first?.value,
                  let date = dateFormatter.date(from: dateStr) else { continue }

            let values = row.metricValues ?? []
            let dau = Int(values[safe: 0]?.value ?? "0") ?? 0
            let wau = Int(values[safe: 1]?.value ?? "0") ?? 0
            let mau = Int(values[safe: 2]?.value ?? "0") ?? 0

            points.append(ActiveUsersPoint(date: date, value: dau, series: .dau))
            points.append(ActiveUsersPoint(date: date, value: wau, series: .wau))
            points.append(ActiveUsersPoint(date: date, value: mau, series: .mau))
        }

        uiState.chartPoints = points

        // Summary: latest value per series
        let sorted = (report.rows ?? []).compactMap { row -> (Date, [Int])? in
            guard let dateStr = row.dimensionValues?.first?.value,
                  let date = dateFormatter.date(from: dateStr) else { return nil }
            let values = row.metricValues ?? []
            let dau = Int(values[safe: 0]?.value ?? "0") ?? 0
            let wau = Int(values[safe: 1]?.value ?? "0") ?? 0
            let mau = Int(values[safe: 2]?.value ?? "0") ?? 0
            return (date, [dau, wau, mau])
        }.sorted { $0.0 > $1.0 }

        if let latest = sorted.first {
            uiState.currentDAU = latest.1[0]
            uiState.currentWAU = latest.1[1]
            uiState.currentMAU = latest.1[2]
        }
    }

    private func createProvider() -> APIProviderFirebase? {
        guard let credentials: FirebaseCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        guard let jsonData = credentials.serviceAccountJSON.data(using: .utf8) else { return nil }
        guard let config = try? FirebaseConfiguration(serviceAccountJSON: jsonData) else { return nil }
        return APIProviderFirebase(configuration: config)
    }
}

