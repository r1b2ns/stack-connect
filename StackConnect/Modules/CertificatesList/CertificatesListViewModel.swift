import Foundation

// MARK: - Protocol

@MainActor
protocol CertificatesListViewModelProtocol: ObservableObject {
    var uiState: CertificatesListUiState { get set }
    func load() async
}

// MARK: - UiState

struct CertificatesListUiState {
    var account: AccountModel
    var certificates: [CertificateModel] = []
    var isLoading = false
    var errorMessage: String?
    var searchQuery = ""

    var filteredCertificates: [CertificateModel] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return certificates }
        return certificates.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.name.lowercased().contains(query) ||
            $0.typeDisplayName.lowercased().contains(query)
        }
    }

    var groupedByType: [(type: String, items: [CertificateModel])] {
        let grouped = Dictionary(grouping: filteredCertificates, by: { $0.typeDisplayName })
        return grouped
            .map { (type: $0.key, items: $0.value.sorted { $0.displayName < $1.displayName }) }
            .sorted { $0.type < $1.type }
    }
}

// MARK: - Implementation

@MainActor
final class CertificatesListViewModel: CertificatesListViewModelProtocol {

    @Published var uiState: CertificatesListUiState

    private let keychain: KeyStorable

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = CertificatesListUiState(account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.errorMessage = nil

        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            uiState.errorMessage = String(localized: "No credentials found for this account")
            uiState.isLoading = false
            Log.print.error("[Certificates] No credentials for account: \(self.uiState.account.name)")
            return
        }

        let connection = AppleAccountConnection(credentials: credentials)

        do {
            let certificates = try await connection.fetchCertificates()
            uiState.certificates = certificates
            Log.print.info("[Certificates] Loaded \(certificates.count) for account: \(self.uiState.account.name)")
        } catch {
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[Certificates] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }
}
