import SwiftUI

// MARK: - Factory

@MainActor
struct NetworkAuditDetailViewFactory {
    /// - Parameter isEmbedded: shown in the Audit's detail column (iPad)
    ///   rather than pushed: it draws its own "Event" bar with Copy URL and
    ///   Export instead of setting the navigation title.
    static func build(summary: NetworkAuditEventSummary, isEmbedded: Bool = false) -> some View {
        NetworkAuditDetailEntry(summary: summary, isEmbedded: isEmbedded)
    }
}

// MARK: - Entry

private struct NetworkAuditDetailEntry: View {
    let isEmbedded: Bool
    @StateObject private var coordinator = NetworkAuditCoordinator()
    @StateObject private var viewModel: NetworkAuditDetailViewModel

    init(summary: NetworkAuditEventSummary, isEmbedded: Bool) {
        self.isEmbedded = isEmbedded
        _viewModel = StateObject(wrappedValue: NetworkAuditDetailViewModel(summary: summary))
    }

    var body: some View {
        NetworkAuditDetailView(viewModel: viewModel, isEmbedded: isEmbedded)
            .environmentObject(coordinator)
    }
}

// MARK: - View

/// One event: what, why, when, and every header and body, with a copy button
/// on each fact. Secret headers stay masked until Face ID.
///
/// Wide (the iPad detail column): "Why this happened" next to "Summary", and
/// the headers next to the body.
struct NetworkAuditDetailView<ViewModel: NetworkAuditDetailViewModelProtocol>: View {

    /// Body lines shown before "View Full Body".
    static var collapsedBodyLines: Int { 40 }
    static var wideMinimumWidth: CGFloat { 640 }

    @ObservedObject var viewModel: ViewModel
    var isEmbedded = false
    @EnvironmentObject private var coordinator: NetworkAuditCoordinator
    @State private var showsFullBody = false

    var body: some View {
        GeometryReader { proxy in
            buildContent(isWide: proxy.size.width >= Self.wideMinimumWidth)
        }
        .background(Color(.systemGroupedBackground))
        .modifier(DetailChromeModifier(isEmbedded: isEmbedded, canExport: viewModel.uiState.event != nil) {
            presentExport()
        })
        .task { await viewModel.load() }
        .toast(message: $viewModel.uiState.toast, duration: 1.6)
        .sheet(item: $coordinator.sheet) { sheet in
            if case .eventExport(let summary) = sheet {
                NetworkAuditEventExportViewFactory.build(summary: summary)
                    .stackFormSheet()
            }
        }
        .trackScreen(.networkAuditDetail)
    }

    private func presentExport() {
        guard let event = viewModel.uiState.event else { return }
        coordinator.presentEventExport(event.summary)
    }

    @ViewBuilder
    private func buildContent(isWide: Bool) -> some View {
        if viewModel.uiState.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let event = viewModel.uiState.event {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isEmbedded {
                        buildEmbeddedBar(event)
                    }
                    buildHeaderCard(event, isWide: isWide)
                    buildInfoSections(isWide: isWide)
                    if event.kind == .http {
                        buildTabs()
                        if isWide {
                            HStack(alignment: .top, spacing: 20) {
                                buildHeadersSection()
                                buildBodySection()
                            }
                        } else {
                            buildHeadersSection()
                            buildBodySection()
                        }
                    }
                    if !isEmbedded {
                        buildExportButton()
                    }
                }
                .padding(.horizontal, isWide ? 24 : 16)
                .padding(.top, isEmbedded ? 4 : 12)
                .padding(.bottom, 40)
            }
        } else {
            ContentUnavailableView(
                String(localized: "Event Not Found", comment: "Network audit detail: the event was deleted (retention or Delete All)."),
                systemImage: "clock.badge.xmark",
                description: Text(String(localized: "It may have been deleted by the retention period.", comment: "Network audit detail: why an event can be missing."))
            )
        }
    }

    // MARK: - Embedded bar (iPad)

    private func buildEmbeddedBar(_ event: NetworkAuditEvent) -> some View {
        HStack(spacing: 4) {
            Text(String(localized: "Event", comment: "Network audit detail: screen title."))
                .font(.headline)
            Spacer()
            if event.url != nil {
                Button {
                    viewModel.copyURL()
                } label: {
                    Label(String(localized: "Copy URL", comment: "Network audit detail (iPad): copies the masked URL."), systemImage: "link")
                        .font(.system(size: 15))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.borderless)
            }
            StackTrackedButton(.networkAuditEventExport, on: .networkAuditDetail) {
                presentExport()
            } label: {
                Label(String(localized: "Export", comment: "Network audit: opens the export sheet."), systemImage: "square.and.arrow.up")
                    .font(.system(size: 15))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderless)
        }
        .padding(.leading, 0)
    }

    // MARK: - Header card

    private func buildHeaderCard(_ event: NetworkAuditEvent, isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                NetworkAuditPill.method(event.method)
                NetworkAuditPill.status(NetworkAuditStatus.title(for: event), isSuccess: event.isSuccess)
                Spacer(minLength: 0)
                NetworkAuditTag(category: event.category)
            }
            .padding(.trailing, 8)

            HStack(spacing: 4) {
                Text(event.host)
                    .font(.system(size: isWide ? 20 : 17, weight: .semibold))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StackCopyIconButton(accessibilityLabel: String(localized: "Copy host", comment: "Accessibility: copies the host of an audit event.")) {
                    viewModel.copy(NetworkAuditInfoRow(label: String(localized: "Host", comment: "Network audit detail: the host."), value: event.host))
                }
                .frame(width: 44, height: 44)
            }
            HStack(spacing: 4) {
                Text(event.path)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(.label).opacity(0.78))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StackCopyIconButton(accessibilityLabel: String(localized: "Copy path", comment: "Accessibility: copies the path of an audit event.")) {
                    viewModel.copy(NetworkAuditInfoRow(label: String(localized: "Path", comment: "Network audit detail: the path and query."), value: event.path))
                }
                .frame(width: 44, height: 44)
            }
            if event.url != nil, !isEmbedded {
                Button {
                    viewModel.copyURL()
                } label: {
                    Label(String(localized: "Copy Full URL", comment: "Network audit detail: copies the masked URL."), systemImage: "link")
                        .font(.system(size: 15))
                        .frame(minHeight: 36)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.leading, isWide ? 18 : 16)
        .padding(.trailing, 8)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Why / Summary

    @ViewBuilder
    private func buildInfoSections(isWide: Bool) -> some View {
        let why = buildInfoSection(
            title: String(localized: "Why This Happened", comment: "Network audit detail: section with origin, account and purpose."),
            rows: viewModel.uiState.whyRows,
            isWide: isWide
        )
        let summary = buildInfoSection(
            title: String(localized: "Summary", comment: "Network audit detail: section with time, duration and sizes."),
            rows: viewModel.uiState.summaryRows,
            isWide: isWide
        )
        if isWide {
            HStack(alignment: .top, spacing: 20) {
                why
                summary
            }
        } else {
            why
            summary
        }
    }

    private func buildInfoSection(title: String, rows: [NetworkAuditInfoRow], isWide: Bool) -> some View {
        StackCardSection(title: title) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    StackCardDivider()
                }
                HStack(spacing: 8) {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Text(row.value)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .textSelection(.enabled)
                    StackCopyIconButton(
                        accessibilityLabel: String(localized: "Copy \(row.label)", comment: "Accessibility: copy button of a row. Argument: the row's label.")
                    ) {
                        viewModel.copy(row)
                    }
                    .frame(width: 44, height: 44)
                }
                .font(.system(size: isWide ? 14 : 15))
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Request / Response

    private func buildTabs() -> some View {
        Picker(
            String(localized: "Direction", comment: "Network audit detail: Request / Response picker label."),
            selection: Binding(get: { viewModel.uiState.tab }, set: { viewModel.selectTab($0) })
        ) {
            ForEach(NetworkAuditDetailTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func buildHeadersSection() -> some View {
        StackCardSection(title: String(localized: "Headers", comment: "Network audit detail: headers section."), footer: headersFooter) {
            Button(String(localized: "Copy All", comment: "Network audit detail: copies every header, secrets masked.")) {
                viewModel.copyAllHeaders()
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.uiState.headers.isEmpty)
        } content: {
            if viewModel.uiState.headers.isEmpty {
                Text(String(localized: "No headers.", comment: "Network audit detail: the request or response had no headers."))
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
            ForEach(Array(viewModel.uiState.headers.enumerated()), id: \.element.id) { index, header in
                if index > 0 {
                    StackCardDivider()
                }
                buildHeaderRow(header)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var headersFooter: String? {
        var lines: [String] = []
        if viewModel.uiState.hasSecretHeaders {
            lines.append(String(localized: "Tokens are stored encrypted and only appear after Face ID. Copying while hidden copies the masked version, and exports always mask them. Only cURL can carry a short-lived token, with Face ID and while it is still valid.", comment: "Network audit detail: footer about secret headers."))
        }
        if viewModel.uiState.isCoreEvent, viewModel.uiState.tab == .request {
            lines.append(String(localized: "Headers added by the network stack while sending (Host, Content-Length, User-Agent and the Apple ID session cookies) aren't listed.", comment: "Network audit detail: known limit of the Rust core's request headers."))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private func buildHeaderRow(_ header: NetworkAuditHeaderRow) -> some View {
        HStack(alignment: header.isSecret ? .top : .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(header.name)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if header.isSecret {
                        NetworkAuditTag.secret
                    }
                }
                Text(header.displayValue)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if header.isSecret {
                    Button {
                        Task { await viewModel.toggleSecrets() }
                    } label: {
                        Label(
                            viewModel.uiState.isRevealed
                                ? String(localized: "Hide Token", comment: "Network audit detail: hides the revealed secret headers.")
                                : String(localized: "Reveal with Face ID", comment: "Network audit detail: reveals the secret headers after Face ID."),
                            systemImage: viewModel.uiState.isRevealed ? "eye.slash" : "faceid"
                        )
                        .font(.system(size: 15))
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StackCopyIconButton(
                accessibilityLabel: String(localized: "Copy \(header.name)", comment: "Accessibility: copy button of a row. Argument: the row's label.")
            ) {
                viewModel.copyHeader(header)
            }
            .frame(width: 44, height: 44)
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, header.isSecret ? 4 : 8)
        .padding(.top, header.isSecret ? 4 : 0)
    }

    // MARK: - Body

    private func buildBodySection() -> some View {
        let body = viewModel.uiState.body
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Body · \(bodyMeta(body))", comment: "Network audit detail: body section. Argument: size and type.").uppercased())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if body.text != nil {
                    Button {
                        viewModel.copyBody()
                    } label: {
                        Label(String(localized: "Copy", comment: "Network audit detail: copies the body."), systemImage: "doc.on.doc")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)

            switch body.content {
            case .text(let text):
                let isLong = text.split(separator: "\n", omittingEmptySubsequences: false).count > Self.collapsedBodyLines
                StackCodeBlock(text: text, lineLimit: showsFullBody || !isLong ? nil : Self.collapsedBodyLines)
                if isLong || body.isTruncated {
                    VStack(spacing: 4) {
                        if isLong {
                            Button(showsFullBody
                                   ? String(localized: "Show Less", comment: "Network audit detail: collapses a long body.")
                                   : String(localized: "View Full Body", comment: "Network audit detail: expands a long body.")) {
                                withAnimation { showsFullBody.toggle() }
                            }
                            .font(.system(size: 15))
                            .frame(minHeight: 44)
                        }
                        if body.isTruncated {
                            Text(String(localized: "Only the first 256 KB of this body were kept.", comment: "Network audit detail: the stored body was cut."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            case .binary:
                buildBodyNote(String(localized: "Binary content, not stored.", comment: "Network audit detail: a binary body (image…)."))
            case .notRecorded:
                buildBodyNote(String(localized: "Not recorded: Full Bodies was off.", comment: "Network audit detail: the body wasn't recorded because the setting was off."))
            case .unavailable:
                buildBodyNote(String(localized: "Not available: the request failed or the body was streamed.", comment: "Network audit detail: the core could not read the body."))
            case .empty:
                buildBodyNote(String(localized: "No body.", comment: "Network audit detail: the request or response had no body."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func buildBodyNote(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func buildExportButton() -> some View {
        StackTrackedButton(.networkAuditEventExport, on: .networkAuditDetail) {
            presentExport()
        } label: {
            Label(String(localized: "Export This Event", comment: "Network audit detail: opens the single-event export sheet."), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(StackBigButtonStyle(kind: .plain))
        .padding(.top, -8)
    }

    private func bodyMeta(_ body: NetworkAuditBody) -> String {
        let size = NetworkAuditFormatting.bytes(body.byteCount)
        guard let type = body.contentType?.split(separator: ";").first.map(String.init), !type.isEmpty else { return size }
        let short = type.split(separator: "/").last.map { $0.uppercased() } ?? type
        return "\(size) · \(short)"
    }
}

/// Pushed: the inline "Event" title with a share button (single-event
/// export). Embedded in the Audit's detail column: nothing, the view draws
/// its own bar so the list keeps the navigation title.
private struct DetailChromeModifier: ViewModifier {
    let isEmbedded: Bool
    let canExport: Bool
    let onExport: () -> Void

    func body(content: Content) -> some View {
        if isEmbedded {
            content
        } else {
            content
                .navigationTitle(String(localized: "Event", comment: "Network audit detail: screen title."))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        StackTrackedButton(.networkAuditEventExport, on: .networkAuditDetail) {
                            onExport()
                        } label: {
                            Label(String(localized: "Export Event", comment: "Network audit: single-event export sheet title."), systemImage: "square.and.arrow.up")
                        }
                        .disabled(!canExport)
                    }
                }
        }
    }
}
