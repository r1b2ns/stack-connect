import SwiftUI

// MARK: - Factory

struct AppPrivacyViewFactory {
    static func build(appId: String, account: AccountModel) -> some View {
        AppPrivacyEntryView(appId: appId, account: account)
    }
}

// MARK: - Entry

private struct AppPrivacyEntryView: View {
    let appId: String
    let account: AccountModel

    @StateObject private var viewModel: AppPrivacyViewModel

    init(appId: String, account: AccountModel) {
        self.appId = appId
        self.account = account
        _viewModel = StateObject(wrappedValue: AppPrivacyViewModel(appId: appId, account: account))
    }

    var body: some View {
        AppPrivacyView(viewModel: viewModel)
    }
}

// MARK: - View

struct AppPrivacyView<ViewModel: AppPrivacyViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "App Privacy"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(
                item: $viewModel.uiState.editingLocalization
            ) { localization in
                EditPrivacySheet(
                    localization: localization,
                    isSaving: viewModel.uiState.isSaving
                ) { updated in
                    Task { await viewModel.save(localization: updated) }
                } onCancel: {
                    viewModel.uiState.editingLocalization = nil
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.localizations.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.localizations.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if let error = viewModel.uiState.error {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Localizations"), systemImage: "hand.raised")
            } description: {
                Text("No localizations found for this app.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            Section {
                ForEach(viewModel.uiState.localizations) { loc in
                    Button {
                        viewModel.uiState.editingLocalization = loc
                    } label: {
                        buildLocaleRow(loc)
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Privacy by Locale")
            } footer: {
                Text("Tap a locale to edit the privacy policy URL, privacy choices URL, and privacy policy text.")
            }

            buildDataCollectionBanner()
        }
    }

    // MARK: - Locale Row

    private func buildLocaleRow(_ loc: AppPrivacyLocaleState) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.localeName)
                    .font(.body)
                    .fontWeight(.medium)

                if let url = loc.privacyPolicyUrl.isEmpty ? nil : loc.privacyPolicyUrl {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(String(localized: "No privacy policy URL"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }

            Spacer()

            if loc.hasAnyPrivacyData {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)
            } else {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .font(.body)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Data Collection Banner

    private func buildDataCollectionBanner() -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)

                    Text("Data collection declarations (privacy nutrition labels) must be managed through the App Store Connect website.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Link(destination: URL(string: "https://appstoreconnect.apple.com/apps/\(viewModel.uiState.appId)/distribution/privacy")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text(String(localized: "Manage Data Collection"))
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Edit Privacy Sheet

struct EditPrivacySheet: View {

    @State var localization: AppPrivacyLocaleState
    let isSaving: Bool
    let onSave: (AppPrivacyLocaleState) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "Privacy Policy URL"),
                        text: $localization.privacyPolicyUrl
                    )
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                } header: {
                    Text("Privacy Policy URL")
                } footer: {
                    Text("A URL that links to your privacy policy.")
                }

                Section {
                    TextField(
                        String(localized: "Privacy Choices URL"),
                        text: $localization.privacyChoicesUrl
                    )
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                } header: {
                    Text("Privacy Choices URL")
                } footer: {
                    Text("A URL where users can modify their privacy preferences.")
                }

                Section {
                    TextEditor(text: $localization.privacyPolicyText)
                        .frame(minHeight: 120)
                } header: {
                    Text("Privacy Policy Text")
                } footer: {
                    Text("Optional inline privacy policy text shown on the App Store.")
                }
            }
            .navigationTitle(localization.localeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(String(localized: "Save")) {
                            onSave(localization)
                        }
                    }
                }
            }
            .disabled(isSaving)
        }
    }
}
