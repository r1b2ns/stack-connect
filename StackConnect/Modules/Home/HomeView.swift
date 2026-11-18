import SwiftUI

// MARK: - Factory

@MainActor
struct HomeViewFactory {
    /// The compact-width root (iPhone, narrow iPad / Mac windows): the Home
    /// stack driven by `coordinator`. Both objects are owned by
    /// `AppRootViewFactory`, so they survive size-class changes.
    static func build(viewModel: HomeViewModel, coordinator: HomeCoordinator) -> some View {
        HomeView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct HomeView<ViewModel: HomeViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: HomeCoordinator
    @Environment(\.analytics) private var analytics
    @State private var isCustomizingWidgets = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            List {
                HomeSyncBanner(syncState: viewModel.uiState.syncState)
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

    private func buildAccountsSection() -> some View {
        Section {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.uiState.providers, id: \.self) { provider in
                    ProviderCardView(provider: provider)
                        .onTapGesture {
                            analytics.track(.buttonTap(.providerButton(for: provider), on: .home))
                            coordinator.navigateToAccountsList(provider)
                        }
                }

                buildSettingsCard()
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
        .listRowBackground(Color.clear)
    }

    private func buildSettingsCard() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 40))
                .foregroundStyle(.gray)

            Text(String(localized: "Settings"))
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            analytics.track(.buttonTap(.settings, on: .home))
            coordinator.navigateToSettings()
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

