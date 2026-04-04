import SwiftUI

// MARK: - Factory

@MainActor
struct SettingsViewFactory {
    static func build() -> some View {
        SettingsEntry()
    }
}

// MARK: - Entry

private struct SettingsEntry: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        SettingsView(viewModel: viewModel)
    }
}

// MARK: - View

struct SettingsView<ViewModel: SettingsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        List {
            buildGeneralSection()
            buildFooterSection()
        }
        .navigationTitle(String(localized: "Settings"))
    }

    // MARK: - Sections

    private func buildGeneralSection() -> some View {
        Section {
            Button {
                homeCoordinator.navigateToSettingsAccounts()
            } label: {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 28)

                    Text(String(localized: "Accounts"))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private func buildFooterSection() -> some View {
        Section {
        } footer: {
            HStack {
                Spacer()
                Text("StackConnect v\(viewModel.uiState.appVersion) (\(viewModel.uiState.buildNumber))")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }
}
