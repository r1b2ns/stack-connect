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
            buildFavoritesSection()
            buildCategorySections()
            buildHiddenSection()
        }
        .navigationTitle(String(localized: "Analytics"))
        .navigationBarTitleDisplayMode(.inline)
        .featureOnboarding(.analytics)
    }

    // MARK: - Favorites

    @ViewBuilder
    private func buildFavoritesSection() -> some View {
        if viewModel.favoriteReports.isEmpty {
            Section {
                buildFavoritesEmptyState()
            }
        } else {
            Section {
                ForEach(viewModel.favoriteReports) { report in
                    buildReportButton(report)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            buildUnfavoriteAction(report)
                            buildHideAction(report)
                        }
                }
            } header: {
                Label(String(localized: "Favorites"), systemImage: "star.fill")
            }
        }
    }

    private func buildFavoritesEmptyState() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(String(localized: "No favorite reports yet"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(String(localized: "Swipe left on a report and tap Favorite to pin it here."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .listRowBackground(Color.clear)
    }

    // MARK: - Categories

    private func buildCategorySections() -> some View {
        ForEach(viewModel.sections, id: \.category.id) { section in
            Section {
                ForEach(section.reports) { report in
                    buildReportButton(report)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            buildFavoriteAction(report)
                            buildHideAction(report)
                        }
                }
            } header: {
                Text(section.category.displayName)
            }
        }
    }

    // MARK: - Hidden

    @ViewBuilder
    private func buildHiddenSection() -> some View {
        if !viewModel.hiddenReports.isEmpty {
            Section {
                if viewModel.isHiddenSectionExpanded {
                    ForEach(viewModel.hiddenReports) { report in
                        buildReportButton(report)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                buildUnhideAction(report)
                            }
                    }
                }
            } header: {
                buildHiddenHeader()
            }
        }
    }

    private func buildHiddenHeader() -> some View {
        Button {
            viewModel.toggleHiddenSection()
        } label: {
            HStack {
                Label(String(localized: "Hidden"), systemImage: "eye.slash")
                Text("(\(viewModel.hiddenReports.count))")
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: viewModel.isHiddenSectionExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row Button

    private func buildReportButton(_ report: AnalyticsCatalogReport) -> some View {
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
        .foregroundStyle(.primary)
    }

    // MARK: - Swipe Actions

    private func buildFavoriteAction(_ report: AnalyticsCatalogReport) -> some View {
        Button {
            viewModel.toggleFavorite(report)
        } label: {
            Label(String(localized: "Favorite"), systemImage: "star.fill")
        }
        .tint(.yellow)
    }

    private func buildUnfavoriteAction(_ report: AnalyticsCatalogReport) -> some View {
        Button {
            viewModel.toggleFavorite(report)
        } label: {
            Label(String(localized: "Unfavorite"), systemImage: "star.slash.fill")
        }
        .tint(.yellow)
    }

    private func buildHideAction(_ report: AnalyticsCatalogReport) -> some View {
        Button {
            viewModel.toggleHidden(report)
        } label: {
            Label(String(localized: "Hide"), systemImage: "eye.slash.fill")
        }
        .tint(.gray)
    }

    private func buildUnhideAction(_ report: AnalyticsCatalogReport) -> some View {
        Button {
            viewModel.toggleHidden(report)
        } label: {
            Label(String(localized: "Unhide"), systemImage: "eye.fill")
        }
        .tint(.blue)
    }

    // MARK: - Rows

    private func buildReportRow(_ report: AnalyticsCatalogReport) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(report.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}
