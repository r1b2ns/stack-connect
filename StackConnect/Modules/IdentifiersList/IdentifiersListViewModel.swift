import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let bundleIdCreated  = Notification.Name("StackConnect.bundleIdCreated")
    static let bundleIdUpdated  = Notification.Name("StackConnect.bundleIdUpdated")
    static let bundleIdDeleted  = Notification.Name("StackConnect.bundleIdDeleted")
}

// MARK: - Protocol

@MainActor
protocol IdentifiersListViewModelProtocol: ObservableObject {
    var uiState: IdentifiersListUiState { get set }
    func load() async
    func create(identifier: String, name: String, platformRaw: String) async -> Bool
    func remove(id: String)
    func upsert(_ model: BundleIdentifierModel)
}

// MARK: - UiState

struct IdentifiersListUiState {
    var account: AccountModel
    var bundleIds: [BundleIdentifierModel] = []
    var isLoading = false
    var isCreating = false
    var errorMessage: String?
    var createErrorMessage: String?
    var searchQuery = ""

    var filtered: [BundleIdentifierModel] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return bundleIds }
        return bundleIds.filter {
            $0.identifier.lowercased().contains(query) ||
            $0.name.lowercased().contains(query)
        }
    }
}

// MARK: - Implementation

@MainActor
final class IdentifiersListViewModel: IdentifiersListViewModelProtocol {

    @Published var uiState: IdentifiersListUiState

    private let keychain: KeyStorable

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = IdentifiersListUiState(account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.errorMessage = nil

        guard let connection = makeConnection() else {
            uiState.isLoading = false
            return
        }

        do {
            uiState.bundleIds = try await connection.fetchBundleIds()
        } catch {
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[Identifiers] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func create(identifier: String, name: String, platformRaw: String) async -> Bool {
        guard let connection = makeConnection() else { return false }

        uiState.isCreating = true
        uiState.createErrorMessage = nil

        do {
            let model = try await connection.createBundleId(
                identifier: identifier,
                name: name,
                platformRaw: platformRaw
            )
            uiState.bundleIds.insert(model, at: 0)
            NotificationCenter.default.post(name: .bundleIdCreated, object: model)
            uiState.isCreating = false
            return true
        } catch {
            uiState.createErrorMessage = error.localizedDescription
            Log.print.error("[Identifiers] Create failed: \(error.localizedDescription)")
            uiState.isCreating = false
            return false
        }
    }

    func remove(id: String) {
        uiState.bundleIds.removeAll { $0.id == id }
    }

    func upsert(_ model: BundleIdentifierModel) {
        if let idx = uiState.bundleIds.firstIndex(where: { $0.id == model.id }) {
            uiState.bundleIds[idx] = model
        } else {
            uiState.bundleIds.insert(model, at: 0)
        }
    }

    private func makeConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            uiState.errorMessage = String(localized: "No credentials found for this account")
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
