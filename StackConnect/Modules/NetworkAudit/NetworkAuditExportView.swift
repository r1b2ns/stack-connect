import SwiftUI

// MARK: - Factory

@MainActor
struct NetworkAuditExportViewFactory {
    static func build(filteredSummaries: [NetworkAuditEventSummary], filterTitle: String) -> some View {
        NetworkAuditExportEntry(filteredSummaries: filteredSummaries, filterTitle: filterTitle)
    }
}

// MARK: - Entry

private struct NetworkAuditExportEntry: View {
    @StateObject private var viewModel: NetworkAuditExportViewModel

    init(filteredSummaries: [NetworkAuditEventSummary], filterTitle: String) {
        _viewModel = StateObject(wrappedValue: NetworkAuditExportViewModel(filteredSummaries: filteredSummaries, filterTitle: filterTitle))
    }

    var body: some View {
        NetworkAuditExportView(viewModel: viewModel)
    }
}

// MARK: - View

/// Export Records sheet: scope, format, bodies, the list of secrets that are
/// always masked, a preview and the share action.
struct NetworkAuditExportView<ViewModel: NetworkAuditExportViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                buildScopeSection()
                buildFormatSection()
                buildBodiesSection()
                NetworkAuditMaskedSecretsSection()
                buildPreviewSection()
                buildExportSection()
            }
            .navigationTitle(String(localized: "Export Records", comment: "Network audit: batch export sheet title."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
        .toast(message: $viewModel.uiState.toast, duration: 1.6)
        .stackShareSheet(item: Binding(
            get: { viewModel.uiState.shareItem },
            set: { if $0 == nil { viewModel.shareDidFinish() } }
        )) { item in
            [item.fileURL]
        }
        .trackScreen(.networkAuditExport)
    }

    // MARK: - Sections

    private func buildScopeSection() -> some View {
        Section(String(localized: "Period", comment: "Network audit export: scope section header.")) {
            ForEach(NetworkAuditExportScope.allCases) { scope in
                StackChoiceRow(
                    title: scope.title,
                    subtitle: scopeDetail(scope),
                    isSelected: viewModel.uiState.scope == scope
                ) {
                    Task { await viewModel.selectScope(scope) }
                }
            }
        }
    }

    private func buildFormatSection() -> some View {
        Section {
            Picker(
                String(localized: "Format", comment: "Network audit export: format picker."),
                selection: Binding(get: { viewModel.uiState.format }, set: { format in Task { await viewModel.selectFormat(format) } })
            ) {
                ForEach(NetworkAuditBatchFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .networkAuditClearRow(top: 0, bottom: 0)
        } header: {
            Text(String(localized: "Format", comment: "Network audit export: format picker."))
        } footer: {
            Text(formatHint(viewModel.uiState.format))
        }
    }

    private func buildBodiesSection() -> some View {
        Section {
            Toggle(isOn: Binding(get: { viewModel.uiState.includeBodies }, set: { enabled in Task { await viewModel.setIncludeBodies(enabled) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Include Bodies", comment: "Network audit export: include bodies toggle."))
                    Text(String(localized: "Content sent and received, already masked", comment: "Network audit export: include bodies subtitle."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!viewModel.uiState.format.supportsBodies)
        }
    }

    private func buildPreviewSection() -> some View {
        Section {
            StackCodeBlock(text: viewModel.uiState.preview.isEmpty ? "—" : viewModel.uiState.preview, lineLimit: 18)
                .networkAuditClearRow(top: 0, bottom: 0)
        } header: {
            HStack {
                Text(String(localized: "Preview", comment: "Network audit export: preview section header."))
                Spacer()
                Button {
                    viewModel.copyPreview()
                } label: {
                    Label(String(localized: "Copy", comment: "Network audit detail: copies the body."), systemImage: "doc.on.doc")
                        .font(.footnote.weight(.semibold))
                }
                .textCase(nil)
            }
        }
    }

    private func buildExportSection() -> some View {
        Section {
            StackTrackedButton(.networkAuditExport, on: .networkAuditExport) {
                Task { await viewModel.export() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.uiState.isExporting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                        Text(String(localized: "Export \(viewModel.uiState.selectedCount) events", comment: "Network audit export: main button. Argument: event count."))
                    }
                }
            }
            .buttonStyle(StackBigButtonStyle())
            .disabled(viewModel.uiState.selectedCount == 0 || viewModel.uiState.isExporting)
            .networkAuditClearRow(top: 0, bottom: 0)
        } footer: {
            Text(String(localized: "The file only leaves the app when you choose where it goes. No copy is kept here, and the export is recorded in the Audit.", comment: "Network audit export: footer."))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func scopeDetail(_ scope: NetworkAuditExportScope) -> String {
        let count = viewModel.uiState.counts[scope] ?? 0
        switch scope {
        case .currentFilter:
            return String(localized: "\(viewModel.uiState.filterTitle) · \(count) events", comment: "Network audit export: detail of the Current Filter scope. Arguments: filter name, count.")
        case .today:
            return String(localized: "\(count) events", comment: "Network audit: count of a day's events.")
        case .entireLog:
            return String(localized: "Last \(viewModel.uiState.retentionDays) days · \(count) events", comment: "Network audit export: detail of the Entire Log scope. Arguments: retention days, count.")
        }
    }

    private func formatHint(_ format: NetworkAuditBatchFormat) -> String {
        switch format {
        case .json:
            return String(localized: "A .json file with every field of each event.", comment: "Network audit export: JSON hint.")
        case .har:
            return String(localized: "HTTP Archive format: opens in Safari, Chrome, Charles and Proxyman.", comment: "Network audit export: HAR hint.")
        case .csv:
            return String(localized: "One line per event, for spreadsheets. Bodies and headers are left out.", comment: "Network audit export: CSV hint.")
        }
    }
}

// MARK: - Masked secrets section

/// The fixed list of what every export masks.
struct NetworkAuditMaskedSecretsSection: View {

    var body: some View {
        Section {
            StackWarningCard(
                title: String(localized: "Secrets Always Leave Masked", comment: "Network audit export: masked secrets section header."),
                text: String(localized: "This can't be turned off, even for what you revealed with Face ID:", comment: "Network audit export: masked secrets lead-in.")
            ) {
                Text(Self.items.map { "• \($0)" }.joined(separator: "\n"))
                    .font(.footnote)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .networkAuditClearRow(top: 0, bottom: 0)
        }
    }

    static var items: [String] {
        [
            String(localized: "Authorization and Bearer tokens (Apple JWT)", comment: "Network audit export: masked secret."),
            String(localized: "Cookies and Set-Cookie of the Apple ID session", comment: "Network audit export: masked secret."),
            String(localized: "Google access_token, refresh_token and id_token", comment: "Network audit export: masked secret."),
            String(localized: "client_secret and private_key of service accounts", comment: "Network audit export: masked secret."),
            String(localized: "Content of imported .p8 keys", comment: "Network audit export: masked secret."),
            String(localized: "API keys in URL parameters (key=…)", comment: "Network audit export: masked secret.")
        ]
    }
}
