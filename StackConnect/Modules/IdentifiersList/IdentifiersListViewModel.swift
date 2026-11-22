import Foundation
import StackProtocols

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
    func refresh() async
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
    var pendingAgreement: Bool = false
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
    private let analytics: AnalyticsTracking

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = IdentifiersListUiState(account: account)
        self.keychain = keychain
        self.analytics = analytics
    }

    /// Maps a `load()` failure onto UI state: a pending Program License Agreement
    /// surfaces as the friendly tip flag, anything else as the generic error message.
    /// Extracted as the injectable test seam because `load()` builds its
    /// `AppleAccountConnection` inline and is otherwise not unit-testable.
    func handleLoadError(_ error: Error) {
        if AppleAPIErrorTranslator.isPendingAgreement(error) {
            uiState.pendingAgreement = true
        } else {
            uiState.errorMessage = error.userFacingMessage
        }
    }

    func load() async {
        _ = await performLoad()
    }

    /// Pull-to-refresh: same load, tracked as a `refresh` action with its outcome.
    func refresh() async {
        let succeeded = await performLoad()
        analytics.track(.action(.refresh, on: .identifiersList, result: succeeded ? .success : .failure))
    }

    private func performLoad() async -> Bool {
        var succeeded = true
        uiState.isLoading = true
        uiState.errorMessage = nil
        uiState.pendingAgreement = false

        guard let connection = makeConnection() else {
            uiState.isLoading = false
            return false
        }

        do {
            uiState.bundleIds = try await connection.fetchBundleIds()
        } catch {
            succeeded = false
            handleLoadError(error)
            Log.print.error("[Identifiers] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
        return succeeded
    }

    func create(identifier: String, name: String, platformRaw: String) async -> Bool {
        analytics.track(.buttonTap(.create, on: .createBundleId))
        let created = await performCreate(identifier: identifier, name: name, platformRaw: platformRaw)
        // `platformRaw` is Apple's platform constant (`IOS`, `MAC_OS`, `UNIVERSAL`).
        analytics.track(.action(.createBundleId, on: .createBundleId, result: created ? .success : .failure, parameters: [
            AnalyticsParameterKey.kind: .string(platformRaw)
        ]))
        return created
    }

    private func performCreate(identifier: String, name: String, platformRaw: String) async -> Bool {
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
            uiState.createErrorMessage = error.userFacingMessage
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
