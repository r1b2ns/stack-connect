import SwiftUI

// MARK: - Factory

@MainActor
struct GooglePlayAppInfoViewFactory {
    static func build(app: GooglePlayAppItem, account: AccountModel) -> some View {
        GooglePlayAppInfoEntry(app: app, account: account)
    }
}

// MARK: - Entry

private struct GooglePlayAppInfoEntry: View {

    @StateObject private var viewModel: GooglePlayAppInfoViewModel

    init(app: GooglePlayAppItem, account: AccountModel) {
        _viewModel = StateObject(wrappedValue: GooglePlayAppInfoViewModel(app: app, account: account))
    }

    var body: some View {
        GooglePlayAppInfoView(viewModel: viewModel)
    }
}

// MARK: - View

struct GooglePlayAppInfoView<ViewModel: GooglePlayAppInfoViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        StackLoadableContent(
            isLoading: viewModel.uiState.isLoading,
            hasContent: viewModel.uiState.hasContent,
            error: viewModel.uiState.error,
            errorReportContext: errorReportContext,
            onRetry: { Task { await viewModel.load() } }
        ) {
            buildContent()
        }
        .navigationTitle(screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Opening this screen is the explicit action that reads through a Play
        // edit — once: coming back from a pushed screen restarts `.task`, which
        // must not open another edit (D14).
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.load() }
        .toast(
            isPresented: $viewModel.uiState.showSyncToast,
            message: String(localized: "Syncing app details...")
        )
    }

    private var screenTitle: String {
        String(localized: "App Details")
    }

    /// Where an error on this screen happened, for its shared report.
    private var errorReportContext: ErrorReportContext {
        ErrorReportContext(screen: screenTitle, account: viewModel.uiState.account, app: viewModel.uiState.app)
    }

    // MARK: - Content

    private func buildContent() -> some View {
        List {
            if let error = viewModel.uiState.error {
                StackInlineErrorSection(message: error, reportContext: errorReportContext)
            }

            if let details = viewModel.uiState.details {
                buildStoreSection(details)
                buildContactSection(details)
            }
        }
    }

    private func buildStoreSection(_ details: GooglePlayAppDetailsModel) -> some View {
        Section {
            LabeledContent(String(localized: "Package Name")) {
                HStack(spacing: 4) {
                    Text(details.packageName)
                        .textSelection(.enabled)
                    CopyButton(text: details.packageName)
                }
            }

            LabeledContent(String(localized: "Default Language")) {
                if let language = details.defaultLanguage {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(GooglePlayLanguage.displayName(for: language))
                        Text(language)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Not set")
                }
            }
        } header: {
            Text("Store")
        }
    }

    private func buildContactSection(_ details: GooglePlayAppDetailsModel) -> some View {
        Section {
            buildContactRow(
                title: String(localized: "Email"),
                icon: "envelope.fill",
                value: details.contactEmail,
                url: details.contactEmail.flatMap(ExternalLinkURL.email)
            )
            buildContactRow(
                title: String(localized: "Phone"),
                icon: "phone.fill",
                value: details.contactPhone,
                url: details.contactPhone.flatMap(ExternalLinkURL.phone)
            )
            buildContactRow(
                title: String(localized: "Website"),
                icon: "safari.fill",
                value: details.contactWebsite,
                url: details.contactWebsite.flatMap(ExternalLinkURL.web)
            )
        } header: {
            Text("Contact Details")
        } footer: {
            Text("Shown to users on your Google Play store listing.")
        }
    }

    /// `url` is `nil` when the stored value isn't a safe link of its kind
    /// (`ExternalLinkURL`): the value is then shown as selectable text.
    @ViewBuilder
    private func buildContactRow(title: String, icon: String, value: String?, url: URL?) -> some View {
        if let value, !value.isEmpty {
            if let url {
                Link(destination: url) {
                    LabeledContent {
                        Text(value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } label: {
                        Label(title, systemImage: icon)
                            .foregroundStyle(.primary)
                    }
                }
            } else {
                LabeledContent {
                    Text(value)
                        .textSelection(.enabled)
                } label: {
                    Label(title, systemImage: icon)
                }
            }
        } else {
            LabeledContent {
                Text("Not set")
            } label: {
                Label(title, systemImage: icon)
            }
        }
    }
}
