import SwiftUI

// MARK: - Factory

@MainActor
struct AppCategoryPickerViewFactory {
    static func build(
        appInfoId: String,
        currentCategoryId: String?,
        currentSubcategoryId: String?,
        currentSecondaryCategoryId: String?,
        currentSecondarySubcategoryId: String?,
        account: AccountModel
    ) -> some View {
        AppCategoryPickerEntry(
            appInfoId: appInfoId,
            currentCategoryId: currentCategoryId,
            currentSubcategoryId: currentSubcategoryId,
            currentSecondaryCategoryId: currentSecondaryCategoryId,
            currentSecondarySubcategoryId: currentSecondarySubcategoryId,
            account: account
        )
    }
}

// MARK: - Entry

private struct AppCategoryPickerEntry: View {
    let appInfoId: String
    let currentCategoryId: String?
    let currentSubcategoryId: String?
    let currentSecondaryCategoryId: String?
    let currentSecondarySubcategoryId: String?
    let account: AccountModel

    @StateObject private var viewModel: AppCategoryPickerViewModel

    init(
        appInfoId: String,
        currentCategoryId: String?,
        currentSubcategoryId: String?,
        currentSecondaryCategoryId: String?,
        currentSecondarySubcategoryId: String?,
        account: AccountModel
    ) {
        self.appInfoId = appInfoId
        self.currentCategoryId = currentCategoryId
        self.currentSubcategoryId = currentSubcategoryId
        self.currentSecondaryCategoryId = currentSecondaryCategoryId
        self.currentSecondarySubcategoryId = currentSecondarySubcategoryId
        self.account = account
        _viewModel = StateObject(
            wrappedValue: AppCategoryPickerViewModel(
                appInfoId: appInfoId,
                currentCategoryId: currentCategoryId,
                currentSubcategoryId: currentSubcategoryId,
                currentSecondaryCategoryId: currentSecondaryCategoryId,
                currentSecondarySubcategoryId: currentSecondarySubcategoryId,
                account: account
            )
        )
    }

    var body: some View {
        AppCategoryPickerView(viewModel: viewModel)
    }
}

// MARK: - View

struct AppCategoryPickerView<ViewModel: AppCategoryPickerViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        Group {
            if viewModel.uiState.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                buildForm()
            }
        }
        .navigationTitle(String(localized: "Category"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { buildToolbar() }
        .task { await viewModel.load() }
        .alert(
            String(localized: "Error"),
            isPresented: Binding(
                get: { viewModel.uiState.error != nil },
                set: { if !$0 { viewModel.uiState.error = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                viewModel.uiState.error = nil
            }
        } message: {
            if let error = viewModel.uiState.error {
                Text(error)
            }
        }
        .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Form

    private func buildForm() -> some View {
        Form {
            // Primary category
            buildPrimaryCategorySection()

            if let primaryCategory = viewModel.uiState.selectedCategory,
               !primaryCategory.subcategories.isEmpty {
                buildPrimarySubcategorySection(for: primaryCategory)
            }

            // Secondary category
            buildSecondaryCategorySection()

            if let secondaryCategory = viewModel.uiState.selectedSecondaryCategory,
               !secondaryCategory.subcategories.isEmpty {
                buildSecondarySubcategorySection(for: secondaryCategory)
            }
        }
    }

    private func buildPrimaryCategorySection() -> some View {
        Section {
            Picker(String(localized: "Primary Category"), selection: $viewModel.uiState.selectedCategoryId) {
                Text(String(localized: "None")).tag(String?.none)
                ForEach(viewModel.uiState.categories) { category in
                    Text(category.displayName).tag(Optional(category.id))
                }
            }
            .onChange(of: viewModel.uiState.selectedCategoryId) { _, _ in
                viewModel.uiState.selectedSubcategoryId = nil
            }
        } header: {
            Text("Primary Category")
        } footer: {
            Text("Choose the primary category that best describes your app.")
        }
    }

    private func buildPrimarySubcategorySection(for category: AppCategoryModel) -> some View {
        Section {
            Picker(String(localized: "Subcategory"), selection: $viewModel.uiState.selectedSubcategoryId) {
                Text(String(localized: "None")).tag(String?.none)
                ForEach(category.subcategories) { sub in
                    Text(sub.subcategoryDisplayName(parentId: category.id))
                        .tag(Optional(sub.id))
                }
            }
        } header: {
            Text("Primary Subcategory")
        }
    }

    private func buildSecondaryCategorySection() -> some View {
        Section {
            Picker(String(localized: "Secondary Category"), selection: $viewModel.uiState.selectedSecondaryCategoryId) {
                Text(String(localized: "None")).tag(String?.none)
                ForEach(viewModel.uiState.categories) { category in
                    Text(category.displayName).tag(Optional(category.id))
                }
            }
            .onChange(of: viewModel.uiState.selectedSecondaryCategoryId) { _, _ in
                viewModel.uiState.selectedSecondarySubcategoryId = nil
            }
        } header: {
            Text("Secondary Category")
        } footer: {
            Text("Optionally, choose a second category to improve discoverability.")
        }
    }

    private func buildSecondarySubcategorySection(for category: AppCategoryModel) -> some View {
        Section {
            Picker(String(localized: "Subcategory"), selection: $viewModel.uiState.selectedSecondarySubcategoryId) {
                Text(String(localized: "None")).tag(String?.none)
                ForEach(category.subcategories) { sub in
                    Text(sub.subcategoryDisplayName(parentId: category.id))
                        .tag(Optional(sub.id))
                }
            }
        } header: {
            Text("Secondary Subcategory")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            if viewModel.uiState.isSaving {
                ProgressView()
            } else {
                Button(String(localized: "Save")) {
                    Task { await viewModel.save() }
                }
                .disabled(viewModel.uiState.selectedCategoryId == nil)
            }
        }
    }
}
