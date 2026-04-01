import Foundation
import APIProviderPlay

// MARK: - Protocol

@MainActor
protocol GooglePlayAppListViewModelProtocol: ObservableObject {
    var uiState: GooglePlayAppListUiState { get set }
    func load() async
    func addApp(packageName: String) async
    func removeApp(_ app: GooglePlayAppItem) async
}

// MARK: - App Item

struct GooglePlayAppItem: Codable, Identifiable, Hashable {
    let id: String
    var packageName: String
    var title: String?
    var isManuallyAdded: Bool

    var displayName: String {
        title ?? packageName
    }
}

// MARK: - UiState

struct GooglePlayAppListUiState {
    var account: AccountModel
    var apps: [GooglePlayAppItem] = []
    var isLoading = false
    var error: String?
    var showAddApp = false
    var isAdding = false
    var addError: String?
    var toastMessage: ToastMessage?
}

// MARK: - Implementation

@MainActor
final class GooglePlayAppListViewModel: GooglePlayAppListViewModelProtocol {

    @Published var uiState: GooglePlayAppListUiState

    private let keychain: KeyStorable
    private let storage: PersistentStorable

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil
    ) {
        self.uiState = GooglePlayAppListUiState(account: account)
        self.keychain = keychain
        self.storage = storage ?? SwiftDataStorable.shared
    }

    // MARK: - Load

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        guard let provider = createProvider() else {
            uiState.error = String(localized: "No credentials found for this account.")
            uiState.isLoading = false
            return
        }

        do {
            // Fetch apps from the Play Developer Reporting API
            var allApps: [GooglePlayAppItem] = []
            var pageToken: String?

            repeat {
                let response = try await provider.request(
                    PlayAPI.reporting.apps.search(pageSize: 100, pageToken: pageToken)
                )

                for app in response.apps ?? [] {
                    guard let packageName = app.packageName else { continue }
                    allApps.append(GooglePlayAppItem(
                        id: packageName,
                        packageName: packageName,
                        title: app.displayName,
                        isManuallyAdded: false
                    ))
                }

                pageToken = response.nextPageToken
            } while pageToken != nil

            // Merge with any manually added apps that aren't in the API response
            let apiPackageNames = Set(allApps.map(\.packageName))
            let manualApps = uiState.apps.filter { $0.isManuallyAdded && !apiPackageNames.contains($0.packageName) }
            allApps.append(contentsOf: manualApps)

            uiState.apps = allApps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            Log.print.info("[GooglePlayAppList] Loaded \(allApps.count) apps")
        } catch {
            // If reporting API fails, try loading from local storage
            Log.print.error("[GooglePlayAppList] Reporting API failed: \(error.localizedDescription)")
            uiState.error = error.localizedDescription
            await loadFromStorage()
        }

        uiState.isLoading = false
    }

    // MARK: - Add App Manually

    func addApp(packageName: String) async {
        let trimmed = packageName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !uiState.apps.contains(where: { $0.packageName == trimmed }) else {
            uiState.addError = String(localized: "This app is already in the list.")
            return
        }

        uiState.isAdding = true
        uiState.addError = nil

        guard let provider = createProvider() else {
            uiState.addError = String(localized: "No credentials found.")
            uiState.isAdding = false
            return
        }

        do {
            // Validate access by creating and immediately deleting an edit
            let edit = try await provider.request(
                PlayAPI.v3.applications(trimmed).edits.insert()
            )

            if let editId = edit.id {
                try? await provider.request(
                    PlayAPI.v3.applications(trimmed).edits.delete(editId: editId)
                )
            }

            let item = GooglePlayAppItem(
                id: trimmed,
                packageName: trimmed,
                title: nil,
                isManuallyAdded: true
            )

            uiState.apps.append(item)
            uiState.apps.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            await saveToStorage()

            uiState.showAddApp = false
            uiState.toastMessage = ToastMessage(String(localized: "App added"), icon: "checkmark.circle.fill")
            Log.print.info("[GooglePlayAppList] Manually added: \(trimmed)")
        } catch {
            uiState.addError = error.localizedDescription
            Log.print.error("[GooglePlayAppList] Add failed: \(error.localizedDescription)")
        }

        uiState.isAdding = false
    }

    // MARK: - Remove

    func removeApp(_ app: GooglePlayAppItem) async {
        uiState.apps.removeAll { $0.id == app.id }
        await saveToStorage()
    }

    // MARK: - Private

    private var storageKey: String {
        "googleplay-apps.\(uiState.account.id)"
    }

    private func loadFromStorage() async {
        do {
            if let stored: [GooglePlayAppItem] = try await storage.fetch(
                [GooglePlayAppItem].self,
                id: storageKey
            ) {
                uiState.apps = stored.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
        } catch {
            Log.print.error("[GooglePlayAppList] Storage load failed: \(error.localizedDescription)")
        }
    }

    private func saveToStorage() async {
        let manualApps = uiState.apps.filter(\.isManuallyAdded)
        do {
            try await storage.save(manualApps, id: storageKey)
        } catch {
            Log.print.error("[GooglePlayAppList] Storage save failed: \(error.localizedDescription)")
        }
    }

    private func createProvider() -> APIProviderPlay? {
        guard let credentials: GooglePlayCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        guard let jsonData = credentials.serviceAccountJSON.data(using: .utf8) else { return nil }
        guard let config = try? PlayConfiguration(serviceAccountJSON: jsonData) else { return nil }
        return APIProviderPlay(configuration: config)
    }
}
