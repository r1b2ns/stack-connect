import Foundation

// MARK: - Protocol

@MainActor
protocol AppPrivacyViewModelProtocol: ObservableObject {
    var uiState: AppPrivacyUiState { get set }
    func load() async
    func save(localization: AppPrivacyLocaleState) async
}

// MARK: - UiState

struct AppPrivacyUiState {
    var appId: String
    var account: AccountModel
    var localizations: [AppPrivacyLocaleState] = []
    var isLoading = false
    var isSaving = false
    var toastMessage: ToastMessage?
    var error: String?
    var editingLocalization: AppPrivacyLocaleState?
}

struct AppPrivacyLocaleState: Identifiable, Hashable {
    let id: String
    var locale: String
    var privacyPolicyUrl: String
    var privacyChoicesUrl: String
    var privacyPolicyText: String

    var localeName: String {
        Locale.current.localizedString(forIdentifier: locale) ?? locale
    }

    var hasAnyPrivacyData: Bool {
        !privacyPolicyUrl.isEmpty || !privacyChoicesUrl.isEmpty || !privacyPolicyText.isEmpty
    }
}

// MARK: - Implementation

@MainActor
final class AppPrivacyViewModel: AppPrivacyViewModelProtocol {

    @Published var uiState: AppPrivacyUiState

    private let keychain: KeyStorable

    init(
        appId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AppPrivacyUiState(appId: appId, account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
                uiState.isLoading = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)
            let (appInfo, _) = try await connection.fetchAppInfo(appId: uiState.appId)

            uiState.localizations = appInfo.localizations.map { loc in
                AppPrivacyLocaleState(
                    id: loc.id,
                    locale: loc.locale,
                    privacyPolicyUrl: loc.privacyPolicyUrl ?? "",
                    privacyChoicesUrl: loc.privacyChoicesUrl ?? "",
                    privacyPolicyText: loc.privacyPolicyText ?? ""
                )
            }.sorted { $0.localeName < $1.localeName }

            Log.print.info("[AppPrivacy] Loaded \(self.uiState.localizations.count) localizations")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppPrivacy] Failed to load: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func save(localization: AppPrivacyLocaleState) async {
        uiState.isSaving = true

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
                uiState.isSaving = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)
            try await connection.updateAppInfoLocalizationPrivacy(
                id: localization.id,
                privacyPolicyUrl: localization.privacyPolicyUrl.isEmpty ? nil : localization.privacyPolicyUrl,
                privacyChoicesUrl: localization.privacyChoicesUrl.isEmpty ? nil : localization.privacyChoicesUrl,
                privacyPolicyText: localization.privacyPolicyText.isEmpty ? nil : localization.privacyPolicyText
            )

            // Update local state
            if let idx = uiState.localizations.firstIndex(where: { $0.id == localization.id }) {
                uiState.localizations[idx] = localization
            }

            uiState.editingLocalization = nil
            uiState.toastMessage = ToastMessage(String(localized: "Privacy updated"), icon: "hand.raised.fill")
            Log.print.info("[AppPrivacy] Updated privacy for \(localization.locale)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to save"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[AppPrivacy] Save failed: \(error.localizedDescription)")
        }

        uiState.isSaving = false
    }
}
