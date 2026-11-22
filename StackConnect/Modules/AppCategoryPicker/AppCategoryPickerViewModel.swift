import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol AppCategoryPickerViewModelProtocol: ObservableObject {
    var uiState: AppCategoryPickerUiState { get set }
    func load() async
    func save() async
}

// MARK: - UiState

struct AppCategoryPickerUiState {
    var appInfoId: String
    var account: AccountModel
    var categories: [AppCategoryModel] = []

    // Primary
    var selectedCategoryId: String?
    var selectedSubcategoryId: String?

    // Secondary
    var selectedSecondaryCategoryId: String?
    var selectedSecondarySubcategoryId: String?

    /// `true` until the first `load()` finishes. The form is only rendered once
    /// `categories` is populated, so the pickers never see a selection without a
    /// matching tag (SwiftUI logs "selection … is invalid" otherwise).
    var isLoading = true
    var isSaving = false
    var error: String?
    var toastMessage: ToastMessage?

    var selectedCategory: AppCategoryModel? {
        categories.first { $0.id == selectedCategoryId }
    }

    var selectedSecondaryCategory: AppCategoryModel? {
        categories.first { $0.id == selectedSecondaryCategoryId }
    }
}

// MARK: - Implementation

@MainActor
final class AppCategoryPickerViewModel: AppCategoryPickerViewModelProtocol {

    @Published var uiState: AppCategoryPickerUiState
    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking

    init(
        appInfoId: String,
        currentCategoryId: String?,
        currentSubcategoryId: String?,
        currentSecondaryCategoryId: String?,
        currentSecondarySubcategoryId: String?,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = AppCategoryPickerUiState(
            appInfoId: appInfoId,
            account: account,
            selectedCategoryId: currentCategoryId,
            selectedSubcategoryId: currentSubcategoryId,
            selectedSecondaryCategoryId: currentSecondaryCategoryId,
            selectedSecondarySubcategoryId: currentSecondarySubcategoryId
        )
        self.keychain = keychain
        self.analytics = analytics
    }

    func load() async {
        uiState.isLoading = true
        var fetched: [AppCategoryModel] = []
        if let connection = createConnection() {
            do {
                fetched = try await connection.fetchAppCategories()
                Log.print.info("[AppCategoryPicker] Loaded \(fetched.count) categories")
            } catch {
                uiState.error = error.userFacingMessage
                Log.print.error("[AppCategoryPicker] Load failed: \(error.localizedDescription)")
            }
        }
        uiState.categories = Self.pickerCategories(fetched: fetched, selectedIds: [
            uiState.selectedCategoryId,
            uiState.selectedSubcategoryId,
            uiState.selectedSecondaryCategoryId,
            uiState.selectedSecondarySubcategoryId
        ])
        uiState.isLoading = false
    }

    /// Categories offered by the pickers: the API list (or the full static ASC
    /// catalog when it is unavailable), extended so every current selection has a
    /// matching tag.
    static func pickerCategories(fetched: [AppCategoryModel], selectedIds: [String?]) -> [AppCategoryModel] {
        let base = fetched.isEmpty ? AppStoreCategoryCatalog.all : fetched
        return AppStoreCategoryCatalog.ensuring(selectedIds, in: base)
    }

    func save() async {
        analytics.track(.buttonTap(.save, on: .appCategoryPicker))
        guard let connection = createConnection() else {
            analytics.track(.action(.updateCategory, on: .appCategoryPicker, result: .failure))
            return
        }
        uiState.isSaving = true
        do {
            try await connection.updateAppInfoCategory(
                appInfoId: uiState.appInfoId,
                primaryCategoryId: uiState.selectedCategoryId,
                subcategoryOneId: uiState.selectedSubcategoryId,
                secondaryCategoryId: uiState.selectedSecondaryCategoryId,
                secondarySubcategoryOneId: uiState.selectedSecondarySubcategoryId
            )
            uiState.toastMessage = ToastMessage(String(localized: "Category updated"), icon: "checkmark.circle.fill")
            Log.print.info("[AppCategoryPicker] Updated category to \(self.uiState.selectedCategoryId ?? "nil")")
            analytics.track(.action(.updateCategory, on: .appCategoryPicker, result: .success))
        } catch {
            analytics.track(.action(.updateCategory, on: .appCategoryPicker, result: .failure))
            uiState.error = error.userFacingMessage
            Log.print.error("[AppCategoryPicker] Save failed: \(error.localizedDescription)")
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
