import SwiftUI

// MARK: - Factory

@MainActor
struct ProfilesListViewFactory {
    static func build(account: AccountModel) -> some View {
        ProfilesListEntry(account: account)
    }
}

// MARK: - Entry

private struct ProfilesListEntry: View {
    @StateObject private var coordinator = ProfilesListCoordinator()
    @StateObject private var viewModel: ProfilesListViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: ProfilesListViewModel(account: account))
    }

    var body: some View {
        ProfilesListView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct ProfilesListView<ViewModel: ProfilesListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Profiles"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search profiles")
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        homeCoordinator.navigateToCreateProfile(viewModel.uiState.account)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "New Profile"))
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .onReceive(NotificationCenter.default.publisher(for: .profileCreated)) { notification in
                if let profile = notification.object as? ProvisioningProfileModel {
                    viewModel.insertProfile(profile)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .profileDeleted)) { notification in
                if let id = notification.object as? String {
                    viewModel.removeProfile(id: id)
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.profiles.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.pendingAgreement {
            PendingAgreementTip()
        } else if viewModel.uiState.filteredProfiles.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if !viewModel.uiState.searchQuery.isEmpty {
            ContentUnavailableView.search(text: viewModel.uiState.searchQuery)
        } else {
            ContentUnavailableView {
                Label(
                    String(localized: "No Profiles"),
                    systemImage: "doc.badge.gearshape"
                )
            } description: {
                if let error = viewModel.uiState.errorMessage {
                    Text(error)
                } else {
                    Text(String(localized: "No provisioning profiles found for this account."))
                }
            }
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.groupedByType, id: \.type) { group in
                Section {
                    ForEach(group.items) { profile in
                        Button {
                            homeCoordinator.navigateToProfileDetail(
                                profile: profile,
                                account: viewModel.uiState.account
                            )
                        } label: {
                            buildRow(profile)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text(group.type)
                }
            }
        }
    }

    private func buildRow(_ profile: ProvisioningProfileModel) -> some View {
        let invalid = profile.isExpired || !profile.isActive
        return HStack(spacing: 12) {
            Image(systemName: "doc.badge.gearshape.fill")
                .font(.title3)
                .foregroundStyle(invalid ? Color.red : Color.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let bundleId = profile.bundleId {
                    Text(bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    buildStateBadge(profile: profile)

                    if let expirationDate = profile.expirationDate {
                        if profile.isExpired {
                            Text(String(localized: "Expired"))
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text(String(localized: "Expires \(expirationDate.formatted(date: .abbreviated, time: .omitted))"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func buildStateBadge(profile: ProvisioningProfileModel) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(profile.isActive && !profile.isExpired ? Color.green : Color.red)
                .frame(width: 6, height: 6)

            Text(profile.isActive ? String(localized: "Active") : String(localized: "Invalid"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
