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

    @State private var showDeleteAllConfirmation = false

    var body: some View {
        List {
            buildGeneralSection()
            buildAppStoreConnectSection()
            buildAboutSection()
            buildDangerSection()
            buildFooterSection()
        }
        .navigationTitle(String(localized: "Settings"))
        .alert(
            String(localized: "Delete All Accounts"),
            isPresented: $showDeleteAllConfirmation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Delete All"), role: .destructive) {
                Task {
                    await viewModel.deleteAllAccounts()
                    homeCoordinator.popToRoot()
                }
            }
        } message: {
            Text(String(localized: "This will permanently delete all accounts, apps, versions, and credentials from the app. This action cannot be undone."))
        }
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

    private func buildAppStoreConnectSection() -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.uiState.preReviewChecklistEnabled },
                set: { viewModel.setPreReviewChecklistEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Check list pre review"))
                        .foregroundStyle(.primary)

                    Text(String(localized: "Shows a checklist before submitting for Apple review"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(String(localized: "App Store Connect"))
        }
    }

    private func buildAboutSection() -> some View {
        Section {
            Link(destination: URL(string: "https://github.com/r1b2ns/stack-connect")!) {
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(.purple)
                        .frame(width: 28)

                    Text(String(localized: "GitHub"))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                homeCoordinator.navigateToLicense()
            } label: {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.gray)
                        .frame(width: 28)

                    Text(String(localized: "License"))
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

    private func buildDangerSection() -> some View {
        Section {
            Button(role: .destructive) {
                showDeleteAllConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                        .frame(width: 28)

                    Text(String(localized: "Delete All Accounts"))
                }
            }
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
