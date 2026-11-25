import SwiftUI

// MARK: - Factory

@MainActor
struct HomeViewFactory {
    /// The Home stack driven by `coordinator`: the Accounts tab of the
    /// compact-width root (`RootTabView`) builds `HomeView` the same way.
    static func build<ViewModel: HomeViewModelProtocol>(viewModel: ViewModel, coordinator: HomeCoordinator) -> some View {
        HomeView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct HomeView<ViewModel: HomeViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: HomeCoordinator
    @State private var isCustomizingWidgets = false

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            List {
                HomeReconnectingTip(appleIds: viewModel.uiState.reconnectingAppleIds)
                HomeSyncBanner(syncState: viewModel.uiState.syncState)
                HomeSignInAgainBanner(viewModel: viewModel)
                HomeAgreementsBanners(viewModel: viewModel)
                HomeTipCard(viewModel: viewModel) {
                    coordinator.navigateToTipJar()
                }
                buildAccountsSection()
                buildWidgetsSection()
            }
            .navigationTitle("StackConnect")
            .trackScreen(.home)
            .homeNavigationDestinations()
            .homePresentations(viewModel: viewModel)
            .toolbar { buildToolbar() }
            .refreshable { await viewModel.refresh() }
            .task {
                viewModel.triggerSync()
                await viewModel.loadDashboard()
            }
            .sheet(isPresented: $isCustomizingWidgets) {
                CustomizeWidgetsView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            StackTrackedButton(.customizeWidgets, on: .home) {
                isCustomizingWidgets = true
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            .accessibilityLabel(String(localized: "Customize Widgets"))
        }
    }

    // MARK: - Widgets Section

    @ViewBuilder
    private func buildWidgetsSection() -> some View {
        if viewModel.uiState.widgets.isEmpty {
            Section {
                HomeWidgetsEmptyState {
                    isCustomizingWidgets = true
                }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(viewModel.uiState.widgets, id: \.id) { widget in
                    HomeWidgetContainerView(widget: widget)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Accounts Section

    /// The Accounts card (Summary style): opens the unified accounts list,
    /// every store grouped and searchable.
    private func buildAccountsSection() -> some View {
        Section {
            StackTrackedButton(.accounts, on: .home) {
                coordinator.navigateToAccountsList()
            } label: {
                StackAccountsSummaryView(summary: viewModel.uiState.accountsSummary)
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Agreement Share Activity Items

extension AgreementSharePayload {

    /// Activity items for the "ask the Account Holder" share sheet: the message
    /// text, with the recipient ("Name <email>") as the share sheet's header title
    /// and a subject for Mail. View-layer mapping (UIKit), kept out of the ViewModel.
    var shareActivityItems: [Any] {
        let icon = UIImage(systemName: "person.crop.circle.badge.exclamationmark.fill")?
            .applyingSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 60))?
            .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
        return [
            StackShareTextItemSource(
                text: message.text,
                subject: message.subject,
                previewTitle: message.recipientTitle,
                previewURL: message.url,
                previewIcon: icon
            )
        ]
    }
}

