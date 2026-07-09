import SwiftUI

// MARK: - Factory

@MainActor
struct AnalyticsReportsViewFactory {
    static func build(appId: String, appName: String, account: AccountModel) -> some View {
        AnalyticsReportsEntry(appId: appId, appName: appName, account: account)
    }
}

// MARK: - Entry

private struct AnalyticsReportsEntry: View {
    let appId: String
    let appName: String
    let account: AccountModel

    @StateObject private var coordinator = AnalyticsReportsCoordinator()
    @StateObject private var viewModel: AnalyticsReportsViewModel

    init(appId: String, appName: String, account: AccountModel) {
        self.appId = appId
        self.appName = appName
        self.account = account
        _viewModel = StateObject(wrappedValue: AnalyticsReportsViewModel(appId: appId, appName: appName, account: account))
    }

    var body: some View {
        AnalyticsReportsView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct AnalyticsReportsView<ViewModel: AnalyticsReportsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        List {
            ForEach(viewModel.sections, id: \.category.id) { section in
                Section {
                    ForEach(section.reports) { report in
                        Button {
                            homeCoordinator.navigateToAnalyticsReportDetail(
                                appId: viewModel.appId,
                                appName: viewModel.appName,
                                report: report,
                                account: viewModel.account
                            )
                        } label: {
                            buildReportRow(report)
                        }
                    }
                } header: {
                    Text(section.category.displayName)
                }
            }
        }
        .navigationTitle(String(localized: "Analytics"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Rows

    private func buildReportRow(_ report: AnalyticsCatalogReport) -> some View {
        HStack(spacing: 12) {
            Text(report.displayName)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}
