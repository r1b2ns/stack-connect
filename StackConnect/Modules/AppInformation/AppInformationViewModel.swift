import Foundation
import AppStoreConnect_Swift_SDK

// MARK: - Protocol

@MainActor
protocol AppInformationViewModelProtocol: ObservableObject {
    var uiState: AppInformationUiState { get set }
    func load() async
    func updateContentRights(_ value: String) async
    func updatePrimaryLocale(_ locale: String) async
}

// MARK: - UiState

struct AppInformationUiState {
    var app: AppModel
    var account: AccountModel
    var isLoading = false
    var isSyncing = false
    var appInfo: AppInfoModel?
    var ageRating: AgeRatingDeclarationModel?
    var error: String?
    var toastMessage: ToastMessage?

    // Editing
    var showContentRightsSheet = false
}

// MARK: - Implementation

@MainActor
final class AppInformationViewModel: AppInformationViewModelProtocol {

    @Published var uiState: AppInformationUiState

    private let keychain: KeyStorable

    init(app: AppModel, account: AccountModel, keychain: KeyStorable = KeychainStorable.shared) {
        self.uiState = AppInformationUiState(app: app, account: account)
        self.keychain = keychain
    }

    func load() async {
        // 1. Load from cache immediately
        let (cachedInfo, cachedRating) = loadFromCache()
        if let cachedInfo {
            uiState.appInfo = cachedInfo
            uiState.ageRating = cachedRating
            uiState.isSyncing = true
        } else {
            uiState.isLoading = true
        }

        guard let connection = createConnection() else {
            uiState.isLoading = false
            uiState.isSyncing = false
            return
        }

        // 2. Sync from API
        do {
            let (appInfo, ageRating) = try await connection.fetchAppInfo(appId: uiState.app.id)
            uiState.appInfo = appInfo
            uiState.ageRating = ageRating
            saveToCache(appInfo: appInfo, ageRating: ageRating)
            Log.print.info("[AppInformation] Loaded app info for \(self.uiState.app.id)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppInformation] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
        uiState.isSyncing = false
    }

    func updateContentRights(_ value: String) async {
        guard let connection = createConnection() else { return }

        do {
            try await connection.updateApp(id: uiState.app.id, contentRightsDeclaration: value)
            uiState.appInfo?.contentRightsDeclaration = value
            uiState.showContentRightsSheet = false
            uiState.toastMessage = ToastMessage(String(localized: "Content rights updated"), icon: "checkmark.circle.fill")
            if let info = uiState.appInfo { saveToCache(appInfo: info, ageRating: uiState.ageRating) }
            Log.print.info("[AppInformation] Updated content rights to \(value)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppInformation] Content rights update failed: \(error.localizedDescription)")
        }
    }

    func updatePrimaryLocale(_ locale: String) async {
        guard let connection = createConnection() else { return }

        do {
            try await connection.updateApp(id: uiState.app.id, primaryLocale: locale)
            uiState.appInfo?.primaryLocale = locale
            uiState.toastMessage = ToastMessage(String(localized: "Primary locale updated"), icon: "checkmark.circle.fill")
            if let info = uiState.appInfo { saveToCache(appInfo: info, ageRating: uiState.ageRating) }
            Log.print.info("[AppInformation] Updated primary locale to \(locale)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppInformation] Primary locale update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Cache

    private func cacheKey(suffix: String) -> String {
        "appInfo.\(uiState.app.id).\(suffix)"
    }

    private func loadFromCache() -> (AppInfoModel?, AgeRatingDeclarationModel?) {
        let defaults = UserDefaults.standard
        let appInfo = defaults.data(forKey: cacheKey(suffix: "info")).flatMap {
            try? JSONDecoder().decode(AppInfoModel.self, from: $0)
        }
        let ageRating = defaults.data(forKey: cacheKey(suffix: "ageRating")).flatMap {
            try? JSONDecoder().decode(AgeRatingDeclarationModel.self, from: $0)
        }
        return (appInfo, ageRating)
    }

    private func saveToCache(appInfo: AppInfoModel, ageRating: AgeRatingDeclarationModel?) {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(appInfo) {
            defaults.set(data, forKey: cacheKey(suffix: "info"))
        }
        if let ar = ageRating, let data = try? JSONEncoder().encode(ar) {
            defaults.set(data, forKey: cacheKey(suffix: "ageRating"))
        }
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
