import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol ManageLocalizationsViewModelProtocol: ObservableObject {
    var uiState: ManageLocalizationsUiState { get set }
    func load() async
    func update(localization: AppInfoLocalizationModel) async
    func delete(localization: AppInfoLocalizationModel) async
    func addLocalization(locale: String, name: String, subtitle: String?) async
}

// MARK: - UiState

struct ManageLocalizationsUiState {
    var appInfoId: String
    var primaryLocale: String
    var account: AccountModel
    var localizations: [AppInfoLocalizationModel] = []
    var isLoading = false
    var isSaving = false
    var error: String?
    var toastMessage: ToastMessage?

    // Edit sheet
    var editingLocalization: AppInfoLocalizationModel?
    var showEditSheet = false

    // Add sheet
    var showAddSheet = false
    var newLocale: String = ""
    var newName: String = ""
    var newSubtitle: String = ""
}

// MARK: - Implementation

@MainActor
final class ManageLocalizationsViewModel: ManageLocalizationsViewModelProtocol {

    @Published var uiState: ManageLocalizationsUiState
    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking

    init(
        appInfoId: String,
        primaryLocale: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = ManageLocalizationsUiState(
            appInfoId: appInfoId,
            primaryLocale: primaryLocale,
            account: account
        )
        self.keychain = keychain
        self.analytics = analytics
    }

    func load() async {
        uiState.isLoading = true
        guard let connection = createConnection() else {
            uiState.isLoading = false
            return
        }
        do {
            uiState.localizations = try await connection.fetchAppInfoLocalizations(appInfoId: uiState.appInfoId)
            Log.print.info("[ManageLocalizations] Loaded \(self.uiState.localizations.count) localizations")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[ManageLocalizations] Load failed: \(error.localizedDescription)")
        }
        uiState.isLoading = false
    }

    func update(localization: AppInfoLocalizationModel) async {
        analytics.track(.buttonTap(.save, on: .editLocalization))
        guard let connection = createConnection() else {
            analytics.track(.action(.updateLocalization, on: .editLocalization, result: .failure))
            return
        }
        uiState.isSaving = true
        do {
            try await connection.updateAppInfoLocalization(
                id: localization.id,
                name: localization.name ?? "",
                subtitle: localization.subtitle
            )
            if let idx = uiState.localizations.firstIndex(where: { $0.id == localization.id }) {
                uiState.localizations[idx] = localization
            }
            uiState.showEditSheet = false
            uiState.editingLocalization = nil
            uiState.toastMessage = ToastMessage(String(localized: "Localization updated"), icon: "checkmark.circle.fill")
            Log.print.info("[ManageLocalizations] Updated localization \(localization.id)")
            analytics.track(.action(.updateLocalization, on: .editLocalization, result: .success))
        } catch {
            analytics.track(.action(.updateLocalization, on: .editLocalization, result: .failure))
            uiState.error = error.localizedDescription
            Log.print.error("[ManageLocalizations] Update failed: \(error.localizedDescription)")
        }
        uiState.isSaving = false
    }

    func delete(localization: AppInfoLocalizationModel) async {
        analytics.track(.buttonTap(.delete, on: .manageLocalizations))
        guard let connection = createConnection() else {
            analytics.track(.action(.deleteLocalization, on: .manageLocalizations, result: .failure))
            return
        }
        do {
            try await connection.deleteAppInfoLocalization(id: localization.id)
            uiState.localizations.removeAll { $0.id == localization.id }
            uiState.toastMessage = ToastMessage(String(localized: "Localization removed"), icon: "checkmark.circle.fill")
            Log.print.info("[ManageLocalizations] Deleted localization \(localization.id)")
            analytics.track(.action(.deleteLocalization, on: .manageLocalizations, result: .success))
        } catch {
            analytics.track(.action(.deleteLocalization, on: .manageLocalizations, result: .failure))
            uiState.error = error.localizedDescription
            Log.print.error("[ManageLocalizations] Delete failed: \(error.localizedDescription)")
        }
    }

    func addLocalization(locale: String, name: String, subtitle: String?) async {
        analytics.track(.buttonTap(.add, on: .addLocalization))
        guard let connection = createConnection() else {
            analytics.track(.action(.createLocalization, on: .addLocalization, result: .failure))
            return
        }
        uiState.isSaving = true
        do {
            let newLoc = try await connection.createAppInfoLocalization(
                appInfoId: uiState.appInfoId,
                locale: locale,
                name: name,
                subtitle: subtitle?.isEmpty == true ? nil : subtitle
            )
            uiState.localizations.append(newLoc)
            uiState.showAddSheet = false
            uiState.newLocale = ""
            uiState.newName = ""
            uiState.newSubtitle = ""
            uiState.toastMessage = ToastMessage(String(localized: "Localization added"), icon: "checkmark.circle.fill")
            Log.print.info("[ManageLocalizations] Added localization for \(locale)")
            analytics.track(.action(.createLocalization, on: .addLocalization, result: .success))
        } catch {
            analytics.track(.action(.createLocalization, on: .addLocalization, result: .failure))
            uiState.error = error.localizedDescription
            Log.print.error("[ManageLocalizations] Add failed: \(error.localizedDescription)")
        }
        uiState.isSaving = false
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
