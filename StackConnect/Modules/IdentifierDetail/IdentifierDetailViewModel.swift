import Foundation
import StackProtocols

// MARK: - Capability catalog

struct CapabilityCatalogEntry: Identifiable, Hashable {
    let raw: String
    var id: String { raw }
    var displayName: String { BundleIdentifierCapabilityModel.displayName(for: raw) }
}

enum CapabilityCatalog {
    /// All capability types known to the API. The portal also surfaces some that are NOT exposed here.
    static let all: [CapabilityCatalogEntry] = [
        "ICLOUD", "IN_APP_PURCHASE", "GAME_CENTER", "PUSH_NOTIFICATIONS", "WALLET",
        "INTER_APP_AUDIO", "MAPS", "ASSOCIATED_DOMAINS", "PERSONAL_VPN", "APP_GROUPS",
        "HEALTHKIT", "HOMEKIT", "WIRELESS_ACCESSORY_CONFIGURATION", "APPLE_PAY",
        "DATA_PROTECTION", "SIRIKIT", "NETWORK_EXTENSIONS", "MULTIPATH", "HOT_SPOT",
        "NFC_TAG_READING", "CLASSKIT", "AUTOFILL_CREDENTIAL_PROVIDER",
        "ACCESS_WIFI_INFORMATION", "NETWORK_CUSTOM_PROTOCOL", "COREMEDIA_HLS_LOW_LATENCY",
        "SYSTEM_EXTENSION_INSTALL", "USER_MANAGEMENT", "APPLE_ID_AUTH"
    ].map { CapabilityCatalogEntry(raw: $0) }
        .sorted { $0.displayName < $1.displayName }
}

// MARK: - Protocol

@MainActor
protocol IdentifierDetailViewModelProtocol: ObservableObject {
    var uiState: IdentifierDetailUiState { get set }
    func load() async
    func rename(to newName: String) async -> Bool
    func delete() async -> Bool
    func enableCapability(typeRaw: String) async
    func disableCapability(id: String) async
}

// MARK: - UiState

struct IdentifierDetailUiState {
    var account: AccountModel
    var bundleId: BundleIdentifierModel
    var capabilities: [BundleIdentifierCapabilityModel] = []
    var isLoadingCapabilities = false
    var pendingCapabilityType: String?
    var isRenaming = false
    var isDeleting = false
    var errorMessage: String?
}

// MARK: - Implementation

@MainActor
final class IdentifierDetailViewModel: IdentifierDetailViewModelProtocol {

    @Published var uiState: IdentifierDetailUiState

    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking

    init(
        account: AccountModel,
        bundleId: BundleIdentifierModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = IdentifierDetailUiState(account: account, bundleId: bundleId)
        self.keychain = keychain
        self.analytics = analytics
    }

    func load() async {
        guard let connection = makeConnection() else { return }

        uiState.isLoadingCapabilities = true
        uiState.errorMessage = nil

        do {
            uiState.capabilities = try await connection.fetchBundleIdCapabilities(bundleId: uiState.bundleId.id)
        } catch {
            uiState.errorMessage = AppleAPIErrorTranslator.friendlyMessage(for: error)
            Log.print.error("[IdentifierDetail] Load capabilities failed: \(error.localizedDescription)")
        }

        uiState.isLoadingCapabilities = false
    }

    func rename(to newName: String) async -> Bool {
        analytics.track(.buttonTap(.save, on: .identifierDetail))
        guard let connection = makeConnection() else {
            analytics.track(.action(.renameBundleId, on: .identifierDetail, result: .failure))
            return false
        }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != uiState.bundleId.name else { return false }

        uiState.isRenaming = true
        uiState.errorMessage = nil

        do {
            try await connection.updateBundleId(id: uiState.bundleId.id, name: trimmed)
            uiState.bundleId = BundleIdentifierModel(
                id: uiState.bundleId.id,
                identifier: uiState.bundleId.identifier,
                name: trimmed,
                platform: uiState.bundleId.platform,
                seedId: uiState.bundleId.seedId
            )
            NotificationCenter.default.post(name: .bundleIdUpdated, object: uiState.bundleId)
            uiState.isRenaming = false
            analytics.track(.action(.renameBundleId, on: .identifierDetail, result: .success))
            return true
        } catch {
            analytics.track(.action(.renameBundleId, on: .identifierDetail, result: .failure))
            uiState.errorMessage = AppleAPIErrorTranslator.friendlyMessage(for: error)
            Log.print.error("[IdentifierDetail] Rename failed: \(error.localizedDescription)")
            uiState.isRenaming = false
            return false
        }
    }

    func delete() async -> Bool {
        analytics.track(.buttonTap(.confirmDelete, on: .identifierDetail))
        guard let connection = makeConnection() else {
            analytics.track(.action(.deleteBundleId, on: .identifierDetail, result: .failure))
            return false
        }

        uiState.isDeleting = true
        uiState.errorMessage = nil

        do {
            try await connection.deleteBundleId(id: uiState.bundleId.id)
            NotificationCenter.default.post(name: .bundleIdDeleted, object: uiState.bundleId.id)
            uiState.isDeleting = false
            analytics.track(.action(.deleteBundleId, on: .identifierDetail, result: .success))
            return true
        } catch {
            analytics.track(.action(.deleteBundleId, on: .identifierDetail, result: .failure))
            uiState.errorMessage = AppleAPIErrorTranslator.friendlyMessage(for: error)
            Log.print.error("[IdentifierDetail] Delete failed: \(error.localizedDescription)")
            uiState.isDeleting = false
            return false
        }
    }

    func enableCapability(typeRaw: String) async {
        analytics.track(.buttonTap(.addCapability, on: .addCapability))
        // `typeRaw` is Apple's capability constant (e.g. `ICLOUD`), never user data.
        let parameters: [String: AnalyticsValue] = [AnalyticsParameterKey.kind: .string(typeRaw)]
        guard let connection = makeConnection() else {
            analytics.track(.action(.enableCapability, on: .addCapability, result: .failure, parameters: parameters))
            return
        }

        uiState.pendingCapabilityType = typeRaw
        uiState.errorMessage = nil

        do {
            let cap = try await connection.enableCapability(
                bundleId: uiState.bundleId.id,
                capabilityTypeRaw: typeRaw
            )
            uiState.capabilities.append(cap)
            analytics.track(.action(.enableCapability, on: .addCapability, result: .success, parameters: parameters))
        } catch {
            analytics.track(.action(.enableCapability, on: .addCapability, result: .failure, parameters: parameters))
            uiState.errorMessage = AppleAPIErrorTranslator.friendlyMessage(for: error)
            Log.print.error("[IdentifierDetail] Enable capability failed: \(error.localizedDescription)")
        }

        uiState.pendingCapabilityType = nil
    }

    func disableCapability(id: String) async {
        analytics.track(.buttonTap(.removeCapability, on: .identifierDetail))
        let removed = uiState.capabilities.first { $0.id == id }
        var parameters: [String: AnalyticsValue] = [:]
        if let type = removed?.capabilityType {
            parameters[AnalyticsParameterKey.kind] = .string(type)
        }
        guard let connection = makeConnection() else {
            analytics.track(.action(.disableCapability, on: .identifierDetail, result: .failure, parameters: parameters))
            return
        }

        uiState.pendingCapabilityType = removed?.capabilityType
        uiState.errorMessage = nil

        do {
            try await connection.disableCapability(capabilityId: id)
            uiState.capabilities.removeAll { $0.id == id }
            analytics.track(.action(.disableCapability, on: .identifierDetail, result: .success, parameters: parameters))
        } catch {
            analytics.track(.action(.disableCapability, on: .identifierDetail, result: .failure, parameters: parameters))
            uiState.errorMessage = AppleAPIErrorTranslator.friendlyMessage(for: error)
            Log.print.error("[IdentifierDetail] Disable capability failed: \(error.localizedDescription)")
        }

        uiState.pendingCapabilityType = nil
    }

    private func makeConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            uiState.errorMessage = String(localized: "No credentials found for this account")
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
