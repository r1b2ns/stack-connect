import SwiftUI

// MARK: - Factory

@MainActor
struct GooglePlayStoreListingsViewFactory {
    static func build(app: GooglePlayAppItem, account: AccountModel) -> some View {
        GooglePlayStoreListingsEntry(app: app, account: account)
    }
}

// MARK: - Entry

private struct GooglePlayStoreListingsEntry: View {

    @StateObject private var viewModel: GooglePlayStoreListingsViewModel

    init(app: GooglePlayAppItem, account: AccountModel) {
        _viewModel = StateObject(wrappedValue: GooglePlayStoreListingsViewModel(app: app, account: account))
    }

    var body: some View {
        GooglePlayStoreListingsView(viewModel: viewModel)
    }
}

// MARK: - View

struct GooglePlayStoreListingsView<ViewModel: GooglePlayStoreListingsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        StackLoadableContent(
            isLoading: viewModel.uiState.isLoading,
            hasContent: viewModel.uiState.hasContent,
            error: viewModel.uiState.error,
            onRetry: { Task { await viewModel.load() } }
        ) {
            buildContent()
        }
        .navigationTitle(String(localized: "Store Listings"))
        .navigationBarTitleDisplayMode(.inline)
        // Opening this screen is the explicit action that reads through a Play
        // edit — once: coming back from a pushed screen restarts `.task`, which
        // must not open another edit (D14).
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.load() }
        .toast(
            isPresented: $viewModel.uiState.showSyncToast,
            message: String(localized: "Syncing store listings...")
        )
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        let listings = viewModel.uiState.listings ?? []
        if listings.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Store Listings"), systemImage: "text.below.photo")
            } description: {
                Text("This app has no store listing yet.")
            }
        } else {
            List {
                if let error = viewModel.uiState.error {
                    StackInlineErrorSection(message: error)
                }

                Section {
                    ForEach(listings) { listing in
                        Button {
                            homeCoordinator.navigateToGooglePlayStoreListingDetail(
                                listing,
                                isDefaultLanguage: listing.isLanguage(viewModel.uiState.defaultLanguage)
                            )
                        } label: {
                            buildListingRow(listing)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Languages (\(listings.count))")
                }
            }
        }
    }

    private func buildListingRow(_ listing: GooglePlayStoreListingModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(GooglePlayLanguage.displayName(for: listing.language))
                        .font(.body)
                        .fontWeight(.medium)

                    if listing.isLanguage(viewModel.uiState.defaultLanguage) {
                        StackCapsuleBadge(title: String(localized: "Default"), color: .green)
                    }
                }

                Text(listing.title ?? listing.language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(listing.language)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
