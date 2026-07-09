import SwiftUI
import Charts

// MARK: - Factory

@MainActor
struct AnalyticsReportDetailViewFactory {
    static func build(appId: String, appName: String, report: AnalyticsCatalogReport, account: AccountModel) -> some View {
        AnalyticsReportDetailEntry(appId: appId, appName: appName, report: report, account: account)
    }
}

// MARK: - Entry

private struct AnalyticsReportDetailEntry: View {
    let appId: String
    let appName: String
    let report: AnalyticsCatalogReport
    let account: AccountModel

    @StateObject private var coordinator = AnalyticsReportDetailCoordinator()
    @StateObject private var viewModel: AnalyticsReportDetailViewModel

    init(appId: String, appName: String, report: AnalyticsCatalogReport, account: AccountModel) {
        self.appId = appId
        self.appName = appName
        self.report = report
        self.account = account
        _viewModel = StateObject(wrappedValue: AnalyticsReportDetailViewModel(
            appId: appId,
            appName: appName,
            report: report,
            account: account
        ))
    }

    var body: some View {
        AnalyticsReportDetailView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct AnalyticsReportDetailView<ViewModel: AnalyticsReportDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    private var granularityBinding: Binding<AnalyticsGranularity> {
        Binding(
            get: { viewModel.uiState.granularity },
            set: { newValue in
                viewModel.uiState.granularity = newValue
                Task { await viewModel.selectGranularity(newValue) }
            }
        )
    }

    var body: some View {
        List {
            buildChartSection()
            buildTableSection()
        }
        .navigationTitle(viewModel.uiState.report.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { buildToolbar() }
        .task { await viewModel.onAppear() }
        .toast(message: $viewModel.uiState.toastMessage)
        .sheet(item: $viewModel.uiState.shareItem) { item in
            AnalyticsShareSheet(activityItems: [item.url])
        }
    }

    // MARK: - Chart Section

    private func buildChartSection() -> some View {
        Section {
            Picker(String(localized: "Granularity"), selection: granularityBinding) {
                ForEach(AnalyticsGranularity.allCases) { granularity in
                    Text(granularity.displayName).tag(granularity)
                }
            }
            .pickerStyle(.segmented)

            buildStoppedBanner()

            buildChartContent()
        }
    }

    /// Warns that report generation was paused due to inactivity (so the chart /
    /// table below may be stale) and, for editors, offers to reactivate it. Only
    /// shown alongside actual data (`.loaded`/`.empty`) — never over the
    /// loading / needs-request / just-requested states.
    @ViewBuilder
    private func buildStoppedBanner() -> some View {
        if viewModel.uiState.isReportStopped, isDataPhase {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Text(String(localized: "Report generation was paused due to inactivity, so this data may be out of date."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }

                if viewModel.uiState.account.canEdit(.analytics) {
                    Button {
                        Task { await viewModel.reactivateReports() }
                    } label: {
                        if viewModel.uiState.isEnabling {
                            ProgressView()
                        } else {
                            Text(String(localized: "Reactivate"))
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.uiState.isEnabling)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(String(localized: "An Admin must reactivate analytics reports for this app."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// The banner rides alongside real content only: `.loaded` (chart) or
    /// `.empty` (no chartable metric, but the request still exists).
    private var isDataPhase: Bool {
        switch viewModel.uiState.phase {
        case .loaded, .empty:
            return true
        case .loading, .needsRequest, .requested:
            return false
        }
    }

    @ViewBuilder
    private func buildChartContent() -> some View {
        switch viewModel.uiState.phase {
        case .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(height: 220)
        case .loaded:
            buildChart()
        case .needsRequest:
            buildNeedsRequestState()
        case .requested(let message):
            buildMessageState(icon: "clock.badge.checkmark", detail: message)
        case .empty(let title, let detail):
            buildMessageState(icon: "tray", title: title, detail: detail)
        }
    }

    private func buildChart() -> some View {
        Chart(viewModel.uiState.series) { point in
            BarMark(
                x: .value("Date", point.label),
                y: .value("Value", point.value)
            )
            .foregroundStyle(.indigo)
        }
        // The exact dates live in the table below; hiding the categorical x-axis
        // keeps the bars readable whatever the point count.
        .chartXAxis(.hidden)
        .frame(height: 240)
        .padding(.vertical, 8)
    }

    private func buildNeedsRequestState() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(String(localized: "Analytics reports aren't enabled for this app yet."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.uiState.account.canEdit(.analytics) {
                Button {
                    Task { await viewModel.enableReports() }
                } label: {
                    if viewModel.uiState.isEnabling {
                        ProgressView()
                    } else {
                        Text(String(localized: "Enable analytics reports"))
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.uiState.isEnabling)
            } else {
                Text(String(localized: "An Admin must enable analytics reports for this app."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func buildMessageState(icon: String, title: String? = nil, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            if let title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Table Section

    @ViewBuilder
    private func buildTableSection() -> some View {
        if case .loaded = viewModel.uiState.phase, !viewModel.uiState.series.isEmpty {
            Section {
                buildTableHeader()
                ForEach(viewModel.uiState.series) { point in
                    buildTableRow(point)
                }
            } header: {
                Text(String(localized: "\(viewModel.uiState.granularity.displayName) data"))
            }
        }
    }

    private func buildTableHeader() -> some View {
        HStack {
            Text(String(localized: "Date"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Spacer()

            Text(String(localized: "Number"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }

    private func buildTableRow(_ point: AnalyticsDataPoint) -> some View {
        HStack {
            Text(point.label)
                .font(.body)

            Spacer()

            Text(Self.formatValue(point.value))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private static func formatValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.share()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(viewModel.uiState.currentFileURL == nil)
            .accessibilityLabel(String(localized: "Share Report"))
        }
    }
}

// MARK: - Share Sheet
//
// Local share sheet that, unlike the account-export one, does NOT delete the
// shared file on completion — the cached report must stay on disk so it can be
// re-shared and reused within its 24h window. (Relocated from the retired
// reports-list module.)

private struct AnalyticsShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
