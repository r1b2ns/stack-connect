import SwiftUI

/// Review of a key file or Google sign-in connection (`AddAccountViewModel`):
/// the name, the role where the store has one, the Google Play developer ID,
/// and what is stored where. "Connect Account" validates and saves.
struct AccountWizardConnectionReview<ViewModel: AddAccountViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let kind: AccountWizardKindConfig
    let method: AccountWizardMethod

    private var state: AddAccountUiState { viewModel.uiState }

    /// Firebase projects picked after a Google sign-in are named after
    /// themselves (one account each): no name to type.
    private var asksForName: Bool {
        !(method == .googleSignIn && state.providerType == .firebase)
    }

    private var asksForRole: Bool {
        kind.supportsRole && state.providerType.supportsAccountRole
    }

    var body: some View {
        if asksForName || asksForRole {
            Section {
                if asksForName {
                    TextField(String(localized: "Account Name"), text: $viewModel.uiState.accountName)
                        .textContentType(.name)
                }
                if asksForRole {
                    Picker(String(localized: "Role"), selection: $viewModel.uiState.role) {
                        ForEach(AccountRole.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("General")
            }
        }

        // Optional (plan U3): only the Users tab needs it.
        if state.providerType == .googlePlay {
            Section {
                LabeledContent(String(localized: "Developer ID")) {
                    TextField(String(localized: "Optional"), text: $viewModel.uiState.googlePlayDeveloperId)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            } header: {
                Text("Developer Account")
            } footer: {
                Text("Needed only to manage users. It's the number in Play Console › Settings › Developer account (also in every Play Console URL). You can add it later in Account Settings.")
            }
        }

        AccountWizardSummarySection(rows: summaryRows)

        if let error = state.validationError {
            AccountWizardErrorSection(message: error)
        }
    }

    private var summaryRows: [AccountWizardSummarySection.Row] {
        var rows: [AccountWizardSummarySection.Row] = [
            .init(title: String(localized: "Type", comment: "Account wizard review: the account type."),
                  value: AccountWizardCopy.title(of: kind.kind)),
            .init(title: String(localized: "Connection", comment: "Account wizard review: how the account connects."),
                  value: AccountWizardCopy.label(of: method))
        ]
        if method == .googleSignIn {
            let picked = state.google.selectableItems
                .filter { state.google.selectedIds.contains($0.id) }
                .map(\.resource.title)
            if !picked.isEmpty {
                rows.append(.init(
                    title: state.providerType == .googlePlay ? String(localized: "Apps") : String(localized: "Projects"),
                    value: picked.formatted(.list(type: .and))
                ))
            }
        }
        rows.append(.init(title: String(localized: "Stored", comment: "Account wizard review: where the credentials are kept."),
                          value: AccountWizardCopy.storage(of: method, savesPassword: false)))
        return rows
    }
}
