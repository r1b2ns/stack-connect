import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let deviceCreated = Notification.Name("StackConnect.deviceCreated")
    static let deviceUpdated = Notification.Name("StackConnect.deviceUpdated")
}

// MARK: - Protocol

@MainActor
protocol DevicesListViewModelProtocol: ObservableObject {
    var uiState: DevicesListUiState { get set }
    func load() async
    func create(name: String, platformRaw: String, udid: String) async -> Bool
    func upsert(_ model: DeviceModel)
}

// MARK: - UiState

struct DevicesListUiState {
    var account: AccountModel
    var devices: [DeviceModel] = []
    var isLoading = false
    var isCreating = false
    var errorMessage: String?
    var pendingAgreement: Bool = false
    var createErrorMessage: String?
    var searchQuery = ""

    var filtered: [DeviceModel] {
        let enabled = devices.filter { $0.isEnabled }
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return enabled }
        return enabled.filter {
            $0.name.lowercased().contains(query) ||
            ($0.udid?.lowercased().contains(query) ?? false) ||
            ($0.model?.lowercased().contains(query) ?? false)
        }
    }
}

// MARK: - Implementation

@MainActor
final class DevicesListViewModel: DevicesListViewModelProtocol {

    @Published var uiState: DevicesListUiState

    private let keychain: KeyStorable

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = DevicesListUiState(account: account)
        self.keychain = keychain
    }

    /// Maps a `load()` failure onto UI state: a pending Program License Agreement
    /// surfaces as the friendly tip flag, anything else as the generic error message.
    /// Extracted as the injectable test seam because `load()` builds its
    /// `AppleAccountConnection` inline and is otherwise not unit-testable.
    func handleLoadError(_ error: Error) {
        if AppleAPIErrorTranslator.isPendingAgreement(error) {
            uiState.pendingAgreement = true
        } else {
            uiState.errorMessage = error.localizedDescription
        }
    }

    func load() async {
        uiState.isLoading = true
        uiState.errorMessage = nil
        uiState.pendingAgreement = false

        guard let connection = makeConnection() else {
            uiState.isLoading = false
            return
        }

        do {
            uiState.devices = try await connection.fetchDevices()
        } catch {
            handleLoadError(error)
            Log.print.error("[Devices] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func create(name: String, platformRaw: String, udid: String) async -> Bool {
        guard let connection = makeConnection() else { return false }

        uiState.isCreating = true
        uiState.createErrorMessage = nil

        do {
            let model = try await connection.createDevice(
                name: name,
                platformRaw: platformRaw,
                udid: udid
            )
            uiState.devices.insert(model, at: 0)
            NotificationCenter.default.post(name: .deviceCreated, object: model)
            uiState.isCreating = false
            return true
        } catch {
            uiState.createErrorMessage = error.localizedDescription
            Log.print.error("[Devices] Create failed: \(error.localizedDescription)")
            uiState.isCreating = false
            return false
        }
    }

    func upsert(_ model: DeviceModel) {
        if let idx = uiState.devices.firstIndex(where: { $0.id == model.id }) {
            uiState.devices[idx] = model
        } else {
            uiState.devices.insert(model, at: 0)
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
