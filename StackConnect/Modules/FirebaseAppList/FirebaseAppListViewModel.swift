import Foundation
import APIProviderFirebase

// MARK: - Protocol

@MainActor
protocol FirebaseAppListViewModelProtocol: ObservableObject {
    var uiState: FirebaseAppListUiState { get set }
    func load() async
    func updateNickname(_ app: FirebaseAppModel, newName: String) async
    func fetchConfig(_ app: FirebaseAppModel) async
    func removeApp(_ app: FirebaseAppModel) async
    func createApp(platform: FirebaseAppPlatform, identifier: String, nickname: String, appStoreId: String) async
}

// MARK: - App Model

enum FirebaseAppPlatform: String, Hashable {
    case ios
    case android
    case web
    case unknown

    var displayName: String {
        switch self {
        case .ios:      return "iOS"
        case .android:  return "Android"
        case .web:      return "Web"
        case .unknown:  return "–"
        }
    }

    var iconName: String {
        switch self {
        case .ios:      return "apple.logo"
        case .android:  return "android"
        case .web:      return "globe"
        case .unknown:  return "questionmark.circle"
        }
    }

    var sortOrder: Int {
        switch self {
        case .ios:      return 0
        case .android:  return 1
        case .web:      return 2
        case .unknown:  return 3
        }
    }
}

struct FirebaseAppModel: Identifiable, Hashable {
    let id: String
    var displayName: String
    var appId: String
    var platform: FirebaseAppPlatform
    var bundleId: String?
    var packageName: String?
    var appUrls: [String]?
    var state: String?

    var platformIdentifier: String? {
        bundleId ?? packageName ?? appUrls?.first
    }
}

// MARK: - UiState

struct FirebaseAppListUiState {
    var account: AccountModel
    var project: FirebaseProjectModel
    var apps: [FirebaseAppModel] = []
    var isLoading = false
    var error: String?
    var searchQuery = ""
    var toastMessage: ToastMessage?
    var selectedApp: FirebaseAppModel?
    var showCreateApp = false
    var confirmDeleteApp: FirebaseAppModel?
    var configContent: String?
    var configFilename: String?

    var filteredApps: [FirebaseAppModel] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.appId.lowercased().contains(query) ||
            ($0.platformIdentifier?.lowercased().contains(query) ?? false)
        }
    }

    var iosApps: [FirebaseAppModel] { filteredApps.filter { $0.platform == .ios } }
    var androidApps: [FirebaseAppModel] { filteredApps.filter { $0.platform == .android } }
    var webApps: [FirebaseAppModel] { filteredApps.filter { $0.platform == .web } }
}

// MARK: - Implementation

@MainActor
final class FirebaseAppListViewModel: FirebaseAppListViewModelProtocol {

    @Published var uiState: FirebaseAppListUiState

    private let keychain: KeyStorable

    init(account: AccountModel, project: FirebaseProjectModel, keychain: KeyStorable = KeychainStorable.shared) {
        self.uiState = FirebaseAppListUiState(account: account, project: project)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let provider = createProvider() else {
                uiState.error = String(localized: "No credentials found for this account.")
                uiState.isLoading = false
                return
            }

            // Load all three platforms in parallel
            async let androidResult = fetchAndroidApps(provider: provider)
            async let iosResult = fetchIosApps(provider: provider)
            async let webResult = fetchWebApps(provider: provider)

            let android = await androidResult
            let ios = await iosResult
            let web = await webResult

            var allApps: [FirebaseAppModel] = []
            allApps.append(contentsOf: android)
            allApps.append(contentsOf: ios)
            allApps.append(contentsOf: web)

            uiState.apps = allApps.sorted { a, b in
                if a.platform.sortOrder != b.platform.sortOrder {
                    return a.platform.sortOrder < b.platform.sortOrder
                }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }

            Log.print.info("[Firebase] Loaded \(allApps.count) apps for project \(self.uiState.project.projectId)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[Firebase] Load apps failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func updateNickname(_ app: FirebaseAppModel, newName: String) async {
        guard let provider = createProvider() else { return }
        let projectId = uiState.project.projectId
        let body = PatchDisplayNameRequest(displayName: newName)

        do {
            switch app.platform {
            case .ios:
                _ = try await provider.request(
                    FirebaseAPI.v1beta1.projects.id(projectId).iosApps.id(app.appId).patch(body, updateMask: "displayName")
                )
            case .android:
                _ = try await provider.request(
                    FirebaseAPI.v1beta1.projects.id(projectId).androidApps.id(app.appId).patch(body, updateMask: "displayName")
                )
            case .web:
                _ = try await provider.request(
                    FirebaseAPI.v1beta1.projects.id(projectId).webApps.id(app.appId).patch(body, updateMask: "displayName")
                )
            case .unknown:
                return
            }

            if let idx = uiState.apps.firstIndex(where: { $0.id == app.id }) {
                uiState.apps[idx].displayName = newName
            }
            uiState.selectedApp = nil
            uiState.toastMessage = ToastMessage(String(localized: "Nickname updated"), icon: "pencil")
            Log.print.info("[Firebase] Updated nickname for \(app.appId)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to update nickname"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[Firebase] Update nickname failed: \(error.localizedDescription)")
        }
    }

    func fetchConfig(_ app: FirebaseAppModel) async {
        guard let provider = createProvider() else { return }
        let projectId = uiState.project.projectId

        do {
            let endpoint: Request<AppConfigResponse>
            switch app.platform {
            case .ios:
                endpoint = FirebaseAPI.v1beta1.projects.id(projectId).iosApps.id(app.appId).config()
            case .android:
                endpoint = FirebaseAPI.v1beta1.projects.id(projectId).androidApps.id(app.appId).config()
            case .web:
                endpoint = FirebaseAPI.v1beta1.projects.id(projectId).webApps.id(app.appId).config()
            case .unknown:
                return
            }

            let response = try await provider.request(endpoint)

            if let base64 = response.configFileContents,
               let data = Data(base64Encoded: base64),
               let content = String(data: data, encoding: .utf8) {
                uiState.configContent = content
                uiState.configFilename = response.configFilename ?? (app.platform == .ios ? "GoogleService-Info.plist" : "google-services.json")
            } else if app.platform == .web {
                // Web returns structured fields
                var lines: [String] = ["{"]
                if let v = response.apiKey { lines.append("  \"apiKey\": \"\(v)\",") }
                if let v = response.authDomain { lines.append("  \"authDomain\": \"\(v)\",") }
                if let v = response.projectId { lines.append("  \"projectId\": \"\(v)\",") }
                if let v = response.storageBucket { lines.append("  \"storageBucket\": \"\(v)\",") }
                if let v = response.messagingSenderId { lines.append("  \"messagingSenderId\": \"\(v)\",") }
                if let v = response.appId { lines.append("  \"appId\": \"\(v)\",") }
                if let v = response.measurementId { lines.append("  \"measurementId\": \"\(v)\"") }
                lines.append("}")
                uiState.configContent = lines.joined(separator: "\n")
                uiState.configFilename = "firebase-config.json"
            }

            Log.print.info("[Firebase] Fetched config for \(app.appId)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to fetch config"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[Firebase] Fetch config failed: \(error.localizedDescription)")
        }
    }

    func removeApp(_ app: FirebaseAppModel) async {
        guard let provider = createProvider() else { return }
        let projectId = uiState.project.projectId

        do {
            switch app.platform {
            case .ios:
                _ = try await provider.request(
                    FirebaseAPI.v1beta1.projects.id(projectId).iosApps.id(app.appId).remove()
                )
            case .android:
                _ = try await provider.request(
                    FirebaseAPI.v1beta1.projects.id(projectId).androidApps.id(app.appId).remove()
                )
            case .web:
                _ = try await provider.request(
                    FirebaseAPI.v1beta1.projects.id(projectId).webApps.id(app.appId).remove()
                )
            case .unknown:
                return
            }

            uiState.apps.removeAll { $0.id == app.id }
            uiState.toastMessage = ToastMessage(String(localized: "App removed"), icon: "trash")
            Log.print.info("[Firebase] Removed app \(app.appId)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to remove app"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[Firebase] Remove app failed: \(error.localizedDescription)")
        }
    }

    func createApp(platform: FirebaseAppPlatform, identifier: String, nickname: String, appStoreId: String) async {
        guard let provider = createProvider() else { return }
        let projectId = uiState.project.projectId
        let displayName = nickname.isEmpty ? nil : nickname

        do {
            switch platform {
            case .ios:
                let body = CreateIosAppRequest(
                    bundleId: identifier,
                    displayName: displayName,
                    appStoreId: appStoreId.isEmpty ? nil : appStoreId
                )
                _ = try await provider.request(
                    FirebaseAPI.v1beta1.projects.id(projectId).iosApps.post(body)
                )
            case .android:
                let body = CreateAndroidAppRequest(
                    packageName: identifier,
                    displayName: displayName
                )
                _ = try await provider.request(
                    FirebaseAPI.v1beta1.projects.id(projectId).androidApps.post(body)
                )
            case .web:
                let body = CreateWebAppRequest(displayName: displayName)
                _ = try await provider.request(
                    FirebaseAPI.v1beta1.projects.id(projectId).webApps.post(body)
                )
            case .unknown:
                return
            }

            uiState.showCreateApp = false
            uiState.toastMessage = ToastMessage(String(localized: "App created"), icon: "plus.circle.fill")
            await load()
            Log.print.info("[Firebase] Created \(platform.displayName) app")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to create app"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[Firebase] Create app failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func fetchAndroidApps(provider: APIProviderFirebase) async -> [FirebaseAppModel] {
        do {
            let response = try await provider.request(
                FirebaseAPI.v1beta1.projects.id(uiState.project.projectId).androidApps.get(pageSize: 100)
            )
            return (response.apps ?? []).map { app in
                FirebaseAppModel(
                    id: app.appId ?? app.id,
                    displayName: app.displayName ?? app.packageName ?? "–",
                    appId: app.appId ?? "–",
                    platform: .android,
                    packageName: app.packageName,
                    state: app.state?.rawValue
                )
            }
        } catch {
            Log.print.error("[Firebase] Fetch Android apps failed: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchIosApps(provider: APIProviderFirebase) async -> [FirebaseAppModel] {
        do {
            let response = try await provider.request(
                FirebaseAPI.v1beta1.projects.id(uiState.project.projectId).iosApps.get(pageSize: 100)
            )
            return (response.apps ?? []).map { app in
                FirebaseAppModel(
                    id: app.appId ?? app.id,
                    displayName: app.displayName ?? app.bundleId ?? "–",
                    appId: app.appId ?? "–",
                    platform: .ios,
                    bundleId: app.bundleId,
                    state: app.state?.rawValue
                )
            }
        } catch {
            Log.print.error("[Firebase] Fetch iOS apps failed: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchWebApps(provider: APIProviderFirebase) async -> [FirebaseAppModel] {
        do {
            let response = try await provider.request(
                FirebaseAPI.v1beta1.projects.id(uiState.project.projectId).webApps.get(pageSize: 100)
            )
            return (response.apps ?? []).map { app in
                FirebaseAppModel(
                    id: app.appId ?? app.id,
                    displayName: app.displayName ?? "–",
                    appId: app.appId ?? "–",
                    platform: .web,
                    appUrls: app.appUrls,
                    state: app.state?.rawValue
                )
            }
        } catch {
            Log.print.error("[Firebase] Fetch Web apps failed: \(error.localizedDescription)")
            return []
        }
    }

    private func createProvider() -> APIProviderFirebase? {
        guard let credentials: FirebaseCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        guard let jsonData = credentials.serviceAccountJSON.data(using: .utf8) else { return nil }
        guard let config = try? FirebaseConfiguration(serviceAccountJSON: jsonData) else { return nil }
        return APIProviderFirebase(configuration: config)
    }
}
