import SwiftUI

// MARK: - Factory

@MainActor
struct NetworkAuditEventExportViewFactory {
    static func build(summary: NetworkAuditEventSummary) -> some View {
        NetworkAuditEventExportEntry(summary: summary)
    }
}

// MARK: - Entry

private struct NetworkAuditEventExportEntry: View {
    @StateObject private var viewModel: NetworkAuditEventExportViewModel

    init(summary: NetworkAuditEventSummary) {
        _viewModel = StateObject(wrappedValue: NetworkAuditEventExportViewModel(summary: summary))
    }

    var body: some View {
        NetworkAuditEventExportView(viewModel: viewModel)
    }
}

// MARK: - View

/// Export Event sheet: cURL | JSON | HAR | Text, the "Include real token"
/// switch for cURL (Face ID, short-lived and still valid tokens only), body,
/// preview, Copy and Share.
struct NetworkAuditEventExportView<ViewModel: NetworkAuditEventExportViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                buildEventSection()
                buildFormatSection()
                if viewModel.uiState.showsTokenToggle {
                    buildCredentialSection()
                    if !viewModel.uiState.isAppTelemetry {
                        buildCredentialRulesSection()
                    }
                }
                buildSecretNoteSection()
                buildBodySection()
                buildPreviewSection()
                buildActionsSection()
            }
            .navigationTitle(String(localized: "Export Event", comment: "Network audit: single-event export sheet title."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
        .toast(message: $viewModel.uiState.toast, duration: 1.8)
        .stackShareSheet(item: Binding(
            get: { viewModel.uiState.shareItem },
            set: { if $0 == nil { viewModel.shareDidFinish() } }
        )) { item in
            [item.fileURL]
        }
        .trackScreen(.networkAuditEventExport)
    }

    // MARK: - Sections

    @ViewBuilder
    private func buildEventSection() -> some View {
        if let event = viewModel.uiState.event {
            Section {
                HStack(spacing: 8) {
                    NetworkAuditPill(title: event.method, isMonospaced: true, fill: NetworkAuditPalette.blueFill, foreground: NetworkAuditPalette.blueText)
                    Text(event.host)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func buildFormatSection() -> some View {
        Section {
            Picker(
                String(localized: "Format", comment: "Network audit export: format picker."),
                selection: Binding(get: { viewModel.uiState.format }, set: { viewModel.selectFormat($0) })
            ) {
                ForEach(NetworkAuditEventFormat.allCases) { format in
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

    private func buildCredentialSection() -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.uiState.includesRealToken },
                set: { enabled in Task { await viewModel.setIncludeRealToken(enabled) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Include Real Token", comment: "Network audit export: switch that puts the real token in the cURL."))
                        .foregroundStyle(viewModel.uiState.canToggleToken ? Color.primary : Color.secondary)
                    Text(credentialSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!viewModel.uiState.canToggleToken)

            if let validity = validityText {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(validity.isValid ? Color.green : Color(.systemGray))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(validity.text)
                        .font(.subheadline)
                        .foregroundStyle(validity.isValid ? NetworkAuditPalette.greenText : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(String(localized: "Credential", comment: "Network audit export: credential section header."))
        }
    }

    private func buildCredentialRulesSection() -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                buildRule(
                    systemImage: "checkmark.shield.fill",
                    tint: .green,
                    title: String(localized: "Can Leave Unmasked", comment: "Network audit export: title of the rule for short-lived tokens."),
                    text: String(localized: "Short-lived tokens: the App Store Connect JWT (20 min) and the Google access token (1 h).", comment: "Network audit export: which tokens a cURL may carry.")
                )
                buildRule(
                    systemImage: "lock.shield.fill",
                    tint: .orange,
                    title: String(localized: "Always Masked, cURL Included", comment: "Network audit export: title of the rule for long-lived secrets."),
                    text: String(localized: "Apple ID session cookies, refresh_token, OAuth assertions and private keys. They last long or give access to the whole account.", comment: "Network audit export: which secrets never leave unmasked.")
                )
            }
            .padding(.vertical, 2)
        }
        .listSectionSpacing(16)
    }

    private func buildRule(systemImage: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func buildSecretNoteSection() -> some View {
        Section {
            if viewModel.uiState.isAppTelemetry {
                StackWarningCard(systemImage: "lock.shield.fill", title: NetworkAuditAppSecretCopy.title, text: viewModel.uiState.secretNote)
                    .networkAuditClearRow(top: 0, bottom: 0)
            } else {
                StackWarningCard(text: viewModel.uiState.secretNote)
                    .networkAuditClearRow(top: 0, bottom: 0)
            }
        }
        .listSectionSpacing(16)
    }

    private func buildBodySection() -> some View {
        Section {
            Toggle(isOn: Binding(get: { viewModel.uiState.includeBody }, set: { viewModel.setIncludeBody($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Include Body", comment: "Network audit export: include body toggle."))
                    Text(bodySubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func buildPreviewSection() -> some View {
        Section {
            StackCodeBlock(text: viewModel.uiState.preview.isEmpty ? "—" : viewModel.uiState.preview, lineLimit: 24)
                .networkAuditClearRow(top: 0, bottom: 0)
        } header: {
            Text(String(localized: "Preview", comment: "Network audit export: preview section header."))
        }
    }

    private func buildActionsSection() -> some View {
        Section {
            HStack(spacing: 10) {
                Button {
                    viewModel.copy()
                } label: {
                    Label(String(localized: "Copy", comment: "Network audit detail: copies the body."), systemImage: "doc.on.doc")
                }
                .buttonStyle(StackBigButtonStyle(kind: .plain))

                StackTrackedButton(.networkAuditEventExport, on: .networkAuditEventExport) {
                    viewModel.share()
                } label: {
                    Label(String(localized: "Share", comment: "Network audit export: opens the share sheet."), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(StackBigButtonStyle())
            }
            .networkAuditClearRow(top: 0, bottom: 0)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.uiState.includesRealToken {
                    Label(
                        String(localized: "The copy stays on this device, never reaches your Mac or iPad, and is cleared from the clipboard in 2 minutes.", comment: "Network audit export: clipboard note when a token is included."),
                        systemImage: "iphone"
                    )
                }
                Label(
                    String(localized: "Every export is recorded in the Audit, with its format and whether it carried a token.", comment: "Network audit export: every export is audited."),
                    systemImage: "checklist"
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    // MARK: - Helpers

    private var bodySubtitle: String {
        guard let event = viewModel.uiState.event, event.responseBody.byteCount > 0 else {
            return String(localized: "Already masked", comment: "Network audit export: include body subtitle (single event).")
        }
        let size = NetworkAuditFormatting.bytes(event.responseBody.byteCount)
        return String(localized: "\(size) of response, already masked", comment: "Network audit export: include body subtitle. Argument: response size.")
    }

    private var credentialSubtitle: String {
        if viewModel.uiState.isAppTelemetry {
            return NetworkAuditAppSecretCopy.tokenSubtitle
        }
        switch viewModel.uiState.event?.credential?.kind {
        case .appStoreConnectJWT:
            return String(localized: "App Store Connect JWT · asks for Face ID", comment: "Network audit export: the token is an App Store Connect JWT.")
        case .googleAccessToken:
            return String(localized: "Google access token · asks for Face ID", comment: "Network audit export: the token is a Google access token.")
        default:
            return String(localized: "This credential can't leave unmasked", comment: "Network audit export: the token is long-lived or unknown.")
        }
    }

    private var validityText: (text: String, isValid: Bool)? {
        switch viewModel.uiState.tokenInclusion {
        case .available(_, let until):
            let minutes = max(1, Int(until.timeIntervalSinceNow / 60))
            return (String(localized: "Token valid for \(minutes) more min (expires at \(until.formatted(date: .omitted, time: .shortened))).", comment: "Network audit export: remaining validity. Arguments: minutes, time."), true)
        case .expired(_, let at):
            return (String(localized: "Token expired at \(at.formatted(date: .omitted, time: .shortened)). It can't be included: the command would return 401.", comment: "Network audit export: the token expired. Argument: time."), false)
        case .unknownValidity:
            return (String(localized: "The token's expiry isn't known, so it can't be included.", comment: "Network audit export: the token's validity is unknown."), false)
        case .alwaysMasked, .notApplicable, .appTelemetry:
            return nil
        }
    }

    private func formatHint(_ format: NetworkAuditEventFormat) -> String {
        switch format {
        case .curl:
            return String(localized: "A command to repeat the request in Terminal.", comment: "Network audit export: cURL hint.")
        case .json:
            return String(localized: "The whole event in .json: request, response and metadata.", comment: "Network audit export: single-event JSON hint.")
        case .har:
            return String(localized: "HTTP Archive with one entry: opens in Safari, Chrome, Charles and Proxyman.", comment: "Network audit export: single-event HAR hint.")
        case .text:
            return String(localized: "A readable summary, good for pasting in a support ticket or email.", comment: "Network audit export: text hint.")
        }
    }
}
