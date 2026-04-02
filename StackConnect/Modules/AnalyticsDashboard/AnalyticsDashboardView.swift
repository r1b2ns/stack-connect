import SwiftUI
import Charts

// MARK: - Factory

@MainActor
struct AnalyticsDashboardViewFactory {
    static func build(project: FirebaseProjectModel, account: AccountModel) -> some View {
        AnalyticsDashboardEntry(project: project, account: account)
    }
}

// MARK: - Entry

private struct AnalyticsDashboardEntry: View {
    let project: FirebaseProjectModel
    let account: AccountModel

    @StateObject private var viewModel: AnalyticsDashboardViewModel

    init(project: FirebaseProjectModel, account: AccountModel) {
        self.project = project
        self.account = account
        _viewModel = StateObject(wrappedValue: AnalyticsDashboardViewModel(project: project, account: account))
    }

    var body: some View {
        AnalyticsDashboardView(viewModel: viewModel)
    }
}

// MARK: - View

struct AnalyticsDashboardView<ViewModel: AnalyticsDashboardViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Analytics Dashboard"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.uiState.error {
            buildError(error)
        } else {
            buildDashboard()
        }
    }

    private func buildError(_ message: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "Unavailable"), systemImage: "chart.bar.xaxis")
        } description: {
            Text(message)
        } actions: {
            if let urlString = viewModel.uiState.apiActivationURL,
               let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(String(localized: "Enable API"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            }

            Button(String(localized: "Retry")) {
                Task { await viewModel.load() }
            }
        }
    }

    private func buildDashboard() -> some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                buildSummaryCards()
                buildActivityChart()
            }
            .padding(16)
        }
    }

    // MARK: - Summary Cards

    private func buildSummaryCards() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Active Users"))
                .font(.headline)
                .padding(.bottom, 2)

            HStack(spacing: 12) {
                buildSummaryCard(
                    title: String(localized: "Today"),
                    subtitle: String(localized: "DAU"),
                    value: viewModel.uiState.currentDAU,
                    color: .blue
                )
                buildSummaryCard(
                    title: String(localized: "7 Days"),
                    subtitle: String(localized: "WAU"),
                    value: viewModel.uiState.currentWAU,
                    color: .orange
                )
                buildSummaryCard(
                    title: String(localized: "28 Days"),
                    subtitle: String(localized: "MAU"),
                    value: viewModel.uiState.currentMAU,
                    color: .green
                )
            }
        }
    }

    private func buildSummaryCard(title: String, subtitle: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value.formatted())
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Activity Chart

    private func buildActivityChart() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "User activity over time"))
                    .font(.headline)

                Text(String(localized: "Active users in the past 30 days"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.uiState.chartPoints.isEmpty {
                Text(String(localized: "No data available"))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 200)
            } else {
                buildChart()
                buildChartLegend()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func buildChart() -> some View {
        Chart(viewModel.uiState.chartPoints) { point in
            LineMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Users", point.value)
            )
            .foregroundStyle(by: .value("Series", point.series.rawValue))
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2))

            AreaMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Users", point.value)
            )
            .foregroundStyle(by: .value("Series", point.series.rawValue))
            .opacity(0.08)
            .interpolationMethod(.catmullRom)
        }
        .chartForegroundStyleScale([
            ActiveUsersSeries.dau.rawValue: Color.blue,
            ActiveUsersSeries.wau.rawValue: Color.orange,
            ActiveUsersSeries.mau.rawValue: Color.green
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(.separator))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(.separator))
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartLegend(.hidden)
        .frame(height: 220)
    }

    private func buildChartLegend() -> some View {
        HStack(spacing: 16) {
            ForEach(ActiveUsersSeries.allCases) { series in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(series.color)
                        .frame(width: 20, height: 3)
                    Text(series.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Series color helper

extension ActiveUsersSeries {
    var color: Color {
        switch self {
        case .dau: return .blue
        case .wau: return .orange
        case .mau: return .green
        }
    }
}
