import Foundation
import StackProtocols

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
    private let analytics: AnalyticsTracking

    init(
        account: AccountModel,
        device: DeviceModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = DeviceDetailUiState(account: account, device: device)
        self.keychain = keychain
        self.analytics = analytics
    }

    func rename(to newName: String) async -> Bool {
        analytics.track(.buttonTap(.save, on: .deviceDetail))
        guard let connection = makeConnection() else {
            analytics.track(.action(.renameDevice, on: .deviceDetail, result: .failure))
            return false
        }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != uiState.device.name else { return false }

        uiState.isRenaming = true
        uiState.errorMessage = nil

        do {
            try await connection.updateDevice(id: uiState.device.id, name: trimmed, status: nil)
            uiState.device = applyingName(trimmed)
            NotificationCenter.default.post(name: .deviceUpdated, object: uiState.device)
            uiState.isRenaming = false
            analytics.track(.action(.renameDevice, on: .deviceDetail, result: .success))
            return true
        } catch {
            analytics.track(.action(.renameDevice, on: .deviceDetail, result: .failure))
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[DeviceDetail] Rename failed: \(error.localizedDescription)")
            uiState.isRenaming = false
            return false
        }
    }

    func toggleStatus() async {
        analytics.track(.buttonTap(.toggleStatus, on: .deviceDetail))
        let newStatus = uiState.device.isEnabled ? "DISABLED" : "ENABLED"
        let parameters: [String: AnalyticsValue] = [AnalyticsParameterKey.enabled: .bool(newStatus == "ENABLED")]
        guard let connection = makeConnection() else {
            analytics.track(.action(.toggleDeviceStatus, on: .deviceDetail, result: .failure, parameters: parameters))
            return
        }

        uiState.isTogglingStatus = true
        uiState.errorMessage = nil


        do {
            try await connection.updateDevice(id: uiState.device.id, name: nil, status: newStatus)
            uiState.device = applyingStatus(newStatus)
            NotificationCenter.default.post(name: .deviceUpdated, object: uiState.device)
            analytics.track(.action(.toggleDeviceStatus, on: .deviceDetail, result: .success, parameters: parameters))
        } catch {
            analytics.track(.action(.toggleDeviceStatus, on: .deviceDetail, result: .failure, parameters: parameters))
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
