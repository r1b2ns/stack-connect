import Foundation

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

    var isLoading = false
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

    init(
        appInfoId: String,
        currentCategoryId: String?,
        currentSubcategoryId: String?,
        currentSecondaryCategoryId: String?,
        currentSecondarySubcategoryId: String?,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
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
    }

    func load() async {
        uiState.isLoading = true
        guard let connection = createConnection() else {
            uiState.isLoading = false
            return
        }
        do {
            uiState.categories = try await connection.fetchAppCategories()
            Log.print.info("[AppCategoryPicker] Loaded \(self.uiState.categories.count) categories")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppCategoryPicker] Load failed: \(error.localizedDescription)")
        }
        uiState.isLoading = false
    }

    func save() async {
        guard let connection = createConnection() else { return }
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
        } catch {
            uiState.error = error.localizedDescription
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
