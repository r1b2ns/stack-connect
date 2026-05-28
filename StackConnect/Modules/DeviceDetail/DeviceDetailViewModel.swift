import Foundation

// MARK: - Protocol

@MainActor
protocol DeviceDetailViewModelProtocol: ObservableObject {
    var uiState: DeviceDetailUiState { get set }
    func rename(to newName: String) async -> Bool
    func toggleStatus() async
}

// MARK: - UiState

struct DeviceDetailUiState {
    var account: AccountModel
    var device: DeviceModel
    var isRenaming = false
    var isTogglingStatus = false
    var errorMessage: String?
}

// MARK: - Implementation

@MainActor
final class DeviceDetailViewModel: DeviceDetailViewModelProtocol {

    @Published var uiState: DeviceDetailUiState

    private let keychain: KeyStorable

    init(
        account: AccountModel,
        device: DeviceModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = DeviceDetailUiState(account: account, device: device)
        self.keychain = keychain
    }

    func rename(to newName: String) async -> Bool {
        guard let connection = makeConnection() else { return false }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != uiState.device.name else { return false }

        uiState.isRenaming = true
        uiState.errorMessage = nil

        do {
            try await connection.updateDevice(id: uiState.device.id, name: trimmed, status: nil)
            uiState.device = applyingName(trimmed)
            NotificationCenter.default.post(name: .deviceUpdated, object: uiState.device)
            uiState.isRenaming = false
            return true
        } catch {
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[DeviceDetail] Rename failed: \(error.localizedDescription)")
            uiState.isRenaming = false
            return false
        }
    }

    func toggleStatus() async {
        guard let connection = makeConnection() else { return }

        uiState.isTogglingStatus = true
        uiState.errorMessage = nil

        let newStatus = uiState.device.isEnabled ? "DISABLED" : "ENABLED"

        do {
            try await connection.updateDevice(id: uiState.device.id, name: nil, status: newStatus)
            uiState.device = applyingStatus(newStatus)
            NotificationCenter.default.post(name: .deviceUpdated, object: uiState.device)
        } catch {
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[DeviceDetail] Status toggle failed: \(error.localizedDescription)")
        }

        uiState.isTogglingStatus = false
    }

    // MARK: - Private

    private func makeConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            uiState.errorMessage = String(localized: "No credentials found for this account")
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }

    private func applyingName(_ name: String) -> DeviceModel {
        let d = uiState.device
        return DeviceModel(
            id: d.id, name: name, udid: d.udid, platform: d.platform,
            deviceClass: d.deviceClass, model: d.model, status: d.status, addedDate: d.addedDate
        )
    }

    private func applyingStatus(_ status: String) -> DeviceModel {
        let d = uiState.device
        return DeviceModel(
            id: d.id, name: d.name, udid: d.udid, platform: d.platform,
            deviceClass: d.deviceClass, model: d.model, status: status, addedDate: d.addedDate
        )
    }
}
