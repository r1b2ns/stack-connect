import SwiftUI

// MARK: - Factory

@MainActor
struct CertificatesListViewFactory {
    static func build(account: AccountModel) -> some View {
        CertificatesListEntry(account: account)
    }
}

// MARK: - Entry

private struct CertificatesListEntry: View {
    @StateObject private var coordinator = CertificatesListCoordinator()
    @StateObject private var viewModel: CertificatesListViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: CertificatesListViewModel(account: account))
    }

    var body: some View {
        CertificatesListView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct CertificatesListView<ViewModel: CertificatesListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Certificates"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search certificates")
            )
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .onReceive(NotificationCenter.default.publisher(for: .certificateRevoked)) { notification in
                if let id = notification.object as? String {
                    viewModel.removeCertificate(id: id)
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.certificates.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.filteredCertificates.isEmpty {
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
                    String(localized: "No Certificates"),
                    systemImage: "lock.shield"
                )
            } description: {
                if let error = viewModel.uiState.errorMessage {
                    Text(error)
                } else {
                    Text(String(localized: "No certificates found for this account."))
                }
            }
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.groupedByType, id: \.type) { group in
                Section {
                    ForEach(group.items) { cert in
                        Button {
                            homeCoordinator.navigateToCertificateDetail(
                                certificate: cert,
                                account: viewModel.uiState.account
                            )
                        } label: {
                            buildRow(cert)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text(group.type)
                }
            }
        }
    }

    private func buildRow(_ cert: CertificateModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(cert.isExpired ? Color.red : Color.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(cert.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let platform = cert.platform {
                        Text(platform)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if let expirationDate = cert.expirationDate {
                        if cert.isExpired {
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
}
