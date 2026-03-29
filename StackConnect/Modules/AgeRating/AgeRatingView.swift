import SwiftUI

// MARK: - Factory

struct AgeRatingViewFactory {
    static func build(ageRating: AgeRatingDeclarationModel, account: AccountModel) -> some View {
        AgeRatingEntry(ageRating: ageRating, account: account)
    }
}

// MARK: - Entry

private struct AgeRatingEntry: View {
    let ageRating: AgeRatingDeclarationModel
    let account: AccountModel

    @StateObject private var viewModel: AgeRatingViewModel

    init(ageRating: AgeRatingDeclarationModel, account: AccountModel) {
        self.ageRating = ageRating
        self.account = account
        _viewModel = StateObject(wrappedValue: AgeRatingViewModel(ageRating: ageRating, account: account))
    }

    var body: some View {
        AgeRatingView(viewModel: viewModel)
    }
}

// MARK: - View

struct AgeRatingView<ViewModel: AgeRatingViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        Form {
            buildLevelSection(
                header: "Violence",
                rows: [
                    (String(localized: "Cartoon or Fantasy"), $viewModel.uiState.violenceCartoon),
                    (String(localized: "Realistic"), $viewModel.uiState.violenceRealistic),
                    (String(localized: "Prolonged Graphic or Sadistic"), $viewModel.uiState.violenceGraphic),
                ]
            )

            buildLevelSection(
                header: "Sexual Content",
                rows: [
                    (String(localized: "Sexual Content or Nudity"), $viewModel.uiState.sexualContentOrNudity),
                    (String(localized: "Graphic Sexual Content or Nudity"), $viewModel.uiState.sexualContentGraphic),
                    (String(localized: "Mature or Suggestive Themes"), $viewModel.uiState.matureOrSuggestive),
                ]
            )

            buildLevelSection(
                header: "Other Content",
                rows: [
                    (String(localized: "Alcohol, Tobacco or Drug Use"), $viewModel.uiState.alcoholTobacco),
                    (String(localized: "Profanity or Crude Humor"), $viewModel.uiState.profanity),
                    (String(localized: "Horror or Fear Themes"), $viewModel.uiState.horrorOrFear),
                    (String(localized: "Medical or Treatment Information"), $viewModel.uiState.medicalInformation),
                    (String(localized: "Guns or Other Weapons"), $viewModel.uiState.gunsOrOtherWeapons),
                    (String(localized: "Gambling Simulated"), $viewModel.uiState.gamblingSimulated),
                    (String(localized: "Contests"), $viewModel.uiState.contests),
                ]
            )

            buildBoolSection(
                header: "Features",
                rows: [
                    (String(localized: "Gambling and Contests"), $viewModel.uiState.isGambling),
                    (String(localized: "Unrestricted Web Access"), $viewModel.uiState.isUnrestrictedWebAccess),
                    (String(localized: "User Generated Content"), $viewModel.uiState.isUserGeneratedContent),
                    (String(localized: "Advertising"), $viewModel.uiState.isAdvertising),
                ]
            )

            Section {
                Picker(String(localized: "Age Rating Override"), selection: $viewModel.uiState.ageRatingOverride) {
                    ForEach(AgeRatingOverrideV2.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } header: {
                Text("Override")
            }
        }
        .navigationTitle(String(localized: "Age Rating"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.uiState.isSaving {
                    ProgressView()
                } else {
                    Button(String(localized: "Save")) {
                        Task { await viewModel.save() }
                    }
                }
            }
        }
        .disabled(viewModel.uiState.isSaving)
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

    // MARK: - Builders

    private func buildLevelSection(header: String, rows: [(String, Binding<AgeRatingLevel>)]) -> some View {
        Section {
            ForEach(rows, id: \.0) { label, binding in
                Picker(label, selection: binding) {
                    ForEach(AgeRatingLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
            }
        } header: {
            Text(header)
        }
    }

    private func buildBoolSection(header: String, rows: [(String, Binding<Bool>)]) -> some View {
        Section {
            ForEach(rows, id: \.0) { label, binding in
                Toggle(label, isOn: binding)
            }
        } header: {
            Text(header)
        }
    }
}
