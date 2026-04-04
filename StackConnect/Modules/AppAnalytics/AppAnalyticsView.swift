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
                buildDateFilter()
                buildMetricCards()
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Date Filter

    private func buildDateFilter() -> some View {
        Picker(String(localized: "Date Range"), selection: $viewModel.uiState.dateRange) {
            ForEach(AnalyticsDateRange.allCases) { range in
                Text(range.displayName).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.uiState.dateRange) { _, _ in
            Task { await viewModel.load() }
        }
    }

    // MARK: - Metric Cards

    private func buildMetricCards() -> some View {
        VStack(spacing: 12) {
            ForEach(viewModel.uiState.metrics) { metric in
                ChartCardView(metric: metric)
            }
        }
    }
}
