import Foundation
import APIProviderPlay

// MARK: - Protocol

@MainActor
protocol GooglePlayAppListViewModelProtocol: ObservableObject {
    var uiState: GooglePlayAppListUiState { get set }
    func load() async
    func addApp(packageName: String) async
    func removeApp(_ app: GooglePlayAppItem) async
    func refreshApp(_ app: GooglePlayAppItem) async
}

// MARK: - App Item

struct GooglePlayAppItem: Codable, Identifiable, Hashable {
    let id: String
    var packageName: String
    var title: String?
    var defaultLanguage: String?
    var latestVersionName: String?
    var latestTrack: String?
    var addedAt: Date

    var displayName: String {
        title ?? packageName
    }
}

// MARK: - Stored Apps

struct GooglePlayStoredApps: Codable {
    var apps: [GooglePlayAppItem]
}

// MARK: - UiState

struct GooglePlayAppListUiState {
    var account: AccountModel
    var apps: [GooglePlayAppItem] = []
    var isLoading = false
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

        do {
            if let stored: GooglePlayStoredApps = try await storage.fetch(
                GooglePlayStoredApps.self,
                id: storageKey
            ) {
                uiState.apps = stored.apps.sorted { $0.displayName < $1.displayName }
            }
        } catch {
            Log.print.error("[GooglePlayAppList] Failed to load: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    // MARK: - Add App

    func addApp(packageName: String) async {
        let trimmed = packageName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !uiState.apps.contains(where: { $0.packageName == trimmed }) else {
            uiState.addError = String(localized: "This app is already added.")
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
            // Validate by creating an edit (proves we have access to this app)
            let edit = try await provider.request(
                PlayAPI.v3.applications(trimmed).edits.insert()
            )

            guard let editId = edit.id else {
                uiState.addError = String(localized: "Failed to access this application.")
                uiState.isAdding = false
                return
            }

            // Fetch details & listing
            var title: String?
            var defaultLanguage: String?
            var latestVersionName: String?
            var latestTrack: String?

            let details = try? await provider.request(
                PlayAPI.v3.applications(trimmed).edits.details(editId: editId).get()
            )
            defaultLanguage = details?.defaultLanguage

            if let lang = defaultLanguage {
                let listing = try? await provider.request(
                    PlayAPI.v3.applications(trimmed).edits.listings(editId: editId).get(language: lang)
                )
                title = listing?.title
            }

            let tracks = try? await provider.request(
                PlayAPI.v3.applications(trimmed).edits.tracks(editId: editId).list()
            )
            if let production = tracks?.tracks?.first(where: { $0.track == "production" }) {
                latestVersionName = production.releases?.first?.name
                latestTrack = "production"
            } else if let first = tracks?.tracks?.first {
                latestVersionName = first.releases?.first?.name
                latestTrack = first.track
            }

            // Delete the edit (cleanup)
            try? await provider.request(
                PlayAPI.v3.applications(trimmed).edits.delete(editId: editId)
            )

            let item = GooglePlayAppItem(
                id: trimmed,
                packageName: trimmed,
                title: title,
                defaultLanguage: defaultLanguage,
                latestVersionName: latestVersionName,
                latestTrack: latestTrack,
                addedAt: Date()
            )

            uiState.apps.append(item)
            uiState.apps.sort { $0.displayName < $1.displayName }
            await saveApps()

            uiState.showAddApp = false
            uiState.toastMessage = ToastMessage(String(localized: "App added"), icon: "checkmark.circle.fill")
            Log.print.info("[GooglePlayAppList] Added: \(trimmed)")
        } catch {
            uiState.addError = error.localizedDescription
            Log.print.error("[GooglePlayAppList] Add failed: \(error.localizedDescription)")
        }

        uiState.isAdding = false
    }

    // MARK: - Remove

    func removeApp(_ app: GooglePlayAppItem) async {
        uiState.apps.removeAll { $0.id == app.id }
        await saveApps()
    }

    // MARK: - Refresh

    func refreshApp(_ app: GooglePlayAppItem) async {
        guard let provider = createProvider() else { return }

        do {
            let edit = try await provider.request(
                PlayAPI.v3.applications(app.packageName).edits.insert()
            )
            guard let editId = edit.id else { return }

            var updated = app
            let details = try? await provider.request(
                PlayAPI.v3.applications(app.packageName).edits.details(editId: editId).get()
            )
            updated.defaultLanguage = details?.defaultLanguage

            if let lang = updated.defaultLanguage {
                let listing = try? await provider.request(
                    PlayAPI.v3.applications(app.packageName).edits.listings(editId: editId).get(language: lang)
                )
                updated.title = listing?.title
            }

            let tracks = try? await provider.request(
                PlayAPI.v3.applications(app.packageName).edits.tracks(editId: editId).list()
            )
            if let production = tracks?.tracks?.first(where: { $0.track == "production" }) {
                updated.latestVersionName = production.releases?.first?.name
                updated.latestTrack = "production"
            }

            try? await provider.request(
                PlayAPI.v3.applications(app.packageName).edits.delete(editId: editId)
            )

            if let idx = uiState.apps.firstIndex(where: { $0.id == app.id }) {
                uiState.apps[idx] = updated
            }
            await saveApps()
        } catch {
            Log.print.error("[GooglePlayAppList] Refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private var storageKey: String {
        "googleplay-apps.\(uiState.account.id)"
    }

    private func saveApps() async {
        do {
            let stored = GooglePlayStoredApps(apps: uiState.apps)
            try await storage.save(stored, id: storageKey)
        } catch {
            Log.print.error("[GooglePlayAppList] Save failed: \(error.localizedDescription)")
        }
    }

    private func createProvider() -> APIProviderPlay? {
        guard let credentials: GooglePlayCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        guard let jsonData = credentials.serviceAccountJSON.data(using: .utf8) else { return nil }
        guard let config = try? PlayConfiguration(serviceAccountJSON: jsonData) else { return nil }
        return APIProviderPlay(configuration: config)
    }
}
