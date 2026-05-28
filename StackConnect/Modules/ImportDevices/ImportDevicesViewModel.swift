import Foundation

// MARK: - Step

enum ImportDevicesStep: Hashable {
    case pickFile
    case preview
    case importing
    case done
}

// MARK: - Failure record

struct ImportFailure: Identifiable, Hashable {
    let id = UUID()
    let udid: String
    let name: String
    let message: String
}

// MARK: - Protocol

@MainActor
protocol ImportDevicesViewModelProtocol: ObservableObject {
    var uiState: ImportDevicesUiState { get set }
    func loadFile(from url: URL) async
    func toggle(id: UUID)
    func selectAll()
    func deselectAll()
    func startImport() async
    func reset()
}

// MARK: - UiState

struct ImportDevicesUiState {
    var account: AccountModel
    var step: ImportDevicesStep = .pickFile
    var sourceFileName: String?
    var parsed: [ParsedDevice] = []
    var selectedIds: Set<UUID> = []
    var platformRaw: String = "IOS"
    var errorMessage: String?

    // Importing
    var importedCount: Int = 0
    var totalToImport: Int = 0
    var failures: [ImportFailure] = []

    var selectedCount: Int { selectedIds.count }
    var validParsedCount: Int { parsed.filter { $0.looksValid }.count }
}

// MARK: - Implementation

@MainActor
final class ImportDevicesViewModel: ImportDevicesViewModelProtocol {

    @Published var uiState: ImportDevicesUiState

    private let keychain: KeyStorable

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = ImportDevicesUiState(account: account)
        self.keychain = keychain
    }

    // MARK: - Load

    func loadFile(from url: URL) async {
        uiState.errorMessage = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let parsed = try DeviceImportParser.parse(data: data, filename: url.lastPathComponent)
            uiState.parsed = parsed
            uiState.sourceFileName = url.lastPathComponent
            uiState.selectedIds = Set(parsed.filter { $0.looksValid }.map { $0.id })

            // Pick a default platform from the first valid hint.
            if let hint = parsed.compactMap({ $0.platformHint }).first {
                uiState.platformRaw = hint
            }
            uiState.step = .preview
            Log.print.info("[ImportDevices] Parsed \(parsed.count) entries from \(url.lastPathComponent)")
        } catch {
            uiState.errorMessage = error.localizedDescription
            Log.print.error("[ImportDevices] Parse failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Selection

    func toggle(id: UUID) {
        if uiState.selectedIds.contains(id) {
            uiState.selectedIds.remove(id)
        } else {
            uiState.selectedIds.insert(id)
        }
    }

    func selectAll() {
        uiState.selectedIds = Set(uiState.parsed.filter { $0.looksValid }.map { $0.id })
    }

    func deselectAll() {
        uiState.selectedIds.removeAll()
    }

    // MARK: - Import

    func startImport() async {
        let toImport = uiState.parsed.filter { uiState.selectedIds.contains($0.id) }
        guard !toImport.isEmpty else { return }

        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            uiState.errorMessage = String(localized: "No credentials found for this account")
            return
        }

        let connection = AppleAccountConnection(credentials: credentials)

        uiState.step = .importing
        uiState.importedCount = 0
        uiState.totalToImport = toImport.count
        uiState.failures = []
        uiState.errorMessage = nil

        for device in toImport {
            let name = device.name.isEmpty
                ? String(localized: "Imported device")
                : device.name

            do {
                let model = try await connection.createDevice(
                    name: name,
                    platformRaw: device.platformHint ?? uiState.platformRaw,
                    udid: device.udid.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                NotificationCenter.default.post(name: .deviceCreated, object: model)
                uiState.importedCount += 1
            } catch {
                uiState.failures.append(ImportFailure(
                    udid: device.udid,
                    name: device.name,
                    message: error.localizedDescription
                ))
                Log.print.error("[ImportDevices] Failed to register \(device.udid): \(error.localizedDescription)")
            }
        }

        uiState.step = .done
        Log.print.info("[ImportDevices] Done: \(self.uiState.importedCount) ok, \(self.uiState.failures.count) failed")
    }

    func reset() {
        uiState = ImportDevicesUiState(account: uiState.account)
    }
}
