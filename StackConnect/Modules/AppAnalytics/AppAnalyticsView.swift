import SwiftUI

// MARK: - Factory

@MainActor
struct AppAnalyticsViewFactory {
    static func build(appId: String, account: AccountModel) -> some View {
        AppAnalyticsEntryView(appId: appId, account: account)
    }
}

// MARK: - Entry

private struct AppAnalyticsEntryView: View {
    let appId: String
    let account: AccountModel

    @StateObject private var viewModel: AppAnalyticsViewModel

    init(appId: String, account: AccountModel) {
        self.appId = appId
        self.account = account
        _viewModel = StateObject(wrappedValue: AppAnalyticsViewModel(appId: appId, account: account))
    }

    var body: some View {
        AppAnalyticsView(viewModel: viewModel)
    }
}

// MARK: - View

struct AppAnalyticsView<ViewModel: AppAnalyticsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Analytics"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.metrics.allSatisfy({ $0.isLoading }) {
            VStack(spacing: 16) {
                ProgressView()
                Text(String(localized: "Loading analytics..."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(localized: "This may take a moment while we download report data."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.isFirstTimeSetup {
            buildFirstTimeSetup()
        } else if let error = viewModel.uiState.error, viewModel.uiState.metrics.allSatisfy({ $0.dataPoints.isEmpty }) {
            buildErrorState(error)
        } else {
            buildScrollContent()
        }
    }

    private func buildFirstTimeSetup() -> some View {
        ContentUnavailableView {
            Label(String(localized: "Setting Up Analytics"), systemImage: "chart.bar.doc.horizontal")
        } description: {
            Text("We've requested analytics reports for this app. Apple typically takes 24-48 hours to generate the initial data. Please check back later.")
        } actions: {
            Button(String(localized: "Refresh")) {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func buildErrorState(_ error: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "Analytics Unavailable"), systemImage: "chart.bar.xaxis")
        } description: {
            Text(error)
        } actions: {
            Button(String(localized: "Retry")) {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func buildScrollContent() -> some View {
        ScrollView {
            VStack(spacing: 16) {
                buildDateRangeTip()
                buildDateFilterStrip()
                buildMetricCards()
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Date Range Tip

    @ViewBuilder
    private func buildDateRangeTip() -> some View {
        if let minDate = viewModel.uiState.minDate, let maxDate = viewModel.uiState.maxDate {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.subheadline)

                Text(String(localized: "Data available from \(formatDateString(minDate)) to \(formatDateString(maxDate))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(12)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Date Filter Strip

    private func buildDateFilterStrip() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" option
                buildDateChip(label: String(localized: "All"), isSelected: viewModel.uiState.selectedDate == nil) {
                    Task { await viewModel.selectDate(nil) }
                }

                // Individual dates
                ForEach(viewModel.uiState.availableDates, id: \.self) { date in
                    buildDateChip(label: formatDateString(date), isSelected: viewModel.uiState.selectedDate == date) {
                        Task { await viewModel.selectDate(date) }
                    }
                }
            }
        }
    }

    private func buildDateChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                .foregroundStyle(isSelected ? .accent : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metric Cards

    private func buildMetricCards() -> some View {
        VStack(spacing: 12) {
            InstallsDeletesChartView(metric: viewModel.uiState.installsDeletes)
            DownloadsChartView(metric: viewModel.uiState.downloads)

            ForEach(viewModel.uiState.metrics) { metric in
                ChartCardView(metric: metric)
            }
        }
    }

    // MARK: - Helpers

    private func formatDateString(_ dateStr: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        return display.string(from: date)
    }
}
