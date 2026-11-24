import Foundation

// MARK: - Protocol

@MainActor
protocol NetworkAuditDetailViewModelProtocol: ObservableObject {
    var uiState: NetworkAuditDetailUiState { get set }
    func load() async
    func selectTab(_ tab: NetworkAuditDetailTab)
    /// Reveals the secret headers after Face ID, or hides them again.
    func toggleSecrets() async
    func copy(_ row: NetworkAuditInfoRow)
    func copyHeader(_ header: NetworkAuditHeaderRow)
    func copyAllHeaders()
    func copyBody()
    func copyURL()
}

// MARK: - UiState

enum NetworkAuditDetailTab: String, CaseIterable, Identifiable, Sendable {
    case request
    case response

    var id: String { rawValue }

    var title: String {
        switch self {
        case .request: return String(localized: "Request (Sent)", comment: "Network audit detail: tab with what was sent.")
        case .response: return String(localized: "Response (Received)", comment: "Network audit detail: tab with what was received.")
        }
    }
}

/// A label / value line with a copy button ("Why this happened", "Summary").
struct NetworkAuditInfoRow: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let value: String
}

/// A header as displayed: secrets show their masked preview until revealed.
struct NetworkAuditHeaderRow: Identifiable, Equatable {
    let id: String
    let name: String
    let displayValue: String
    let isSecret: Bool
    let isRevealed: Bool
    /// Carried StackConnect's own identifiers (hidden as `[APP]`).
    var isAppData = false
}

struct NetworkAuditDetailUiState {
    var isLoading = true
    var event: NetworkAuditEvent?
    var tab: NetworkAuditDetailTab = .request
    var isRevealed = false
    var whyRows: [NetworkAuditInfoRow] = []
    var summaryRows: [NetworkAuditInfoRow] = []
    var headers: [NetworkAuditHeaderRow] = []
    var body: NetworkAuditBody = .empty
    var toast: ToastMessage?

    var hasSecretHeaders: Bool { headers.contains(where: \.isSecret) }
    /// Recorded by the Rust core, whose HTTP stack adds headers it can't see.
    var isCoreEvent: Bool { event?.source == .rustCore }
    /// StackConnect's own telemetry: secrets are app secrets, never revealable.
    var isAppTelemetry: Bool { event?.isAppTelemetry ?? false }
    /// Something owned by StackConnect was hidden: shows the explanation card.
    var hidesAppValues: Bool { event?.hidesAppValues ?? false }
    /// A secret header can be revealed with Face ID (user-owned credentials
    /// with sealed originals).
    var canRevealSecrets: Bool { hasSecretHeaders && !isAppTelemetry && event?.sealedSecrets != nil }
}

// MARK: - Implementation

@MainActor
final class NetworkAuditDetailViewModel: NetworkAuditDetailViewModelProtocol {

    @Published var uiState = NetworkAuditDetailUiState()

    private let summary: NetworkAuditEventSummary
    private let dependencies: NetworkAuditDependencies
    private var revealedSecrets: [String: String] = [:]

    init(summary: NetworkAuditEventSummary, dependencies: NetworkAuditDependencies? = nil) {
        self.summary = summary
        self.dependencies = dependencies ?? .live
    }

    func load() async {
        // App telemetry events never expose a sealed original, even one stored
        // by an older version (`appTelemetrySanitized`).
        uiState.event = await dependencies.store.event(for: summary)?.sanitizedForDisplay(identity: dependencies.appIdentity)
        uiState.isLoading = false
        rebuild()
    }

    func selectTab(_ tab: NetworkAuditDetailTab) {
        uiState.tab = tab
        rebuild()
    }

    func toggleSecrets() async {
        if uiState.isRevealed {
            revealedSecrets = [:]
            uiState.isRevealed = false
            rebuild()
            return
        }
        guard uiState.canRevealSecrets, let sealed = uiState.event?.sealedSecrets else { return }
        let reason = String(localized: "Reveal the token recorded in the network audit.", comment: "Face ID reason: revealing a recorded token in the network audit.")
        guard await dependencies.authenticator.authenticate(reason: reason) else { return }
        guard let secrets = dependencies.vault.open(sealed) else {
            uiState.toast = ToastMessage(
                String(localized: "The token can't be decrypted on this device.", comment: "Network audit toast: the sealed secrets could not be opened."),
                icon: "exclamationmark.triangle.fill"
            )
            return
        }
        revealedSecrets = secrets
        uiState.isRevealed = true
        rebuild()
    }

    func copy(_ row: NetworkAuditInfoRow) {
        dependencies.pasteboard.copy(row.value, sensitive: false)
        showCopied(row.label)
    }

    func copyHeader(_ header: NetworkAuditHeaderRow) {
        guard let event = uiState.event else { return }
        let stored = storedHeaders(of: event)
        guard let index = Int(header.id.split(separator: ".").last ?? ""), stored.indices.contains(index) else { return }
        let entry = stored[index]
        if entry.isSecret, header.isRevealed, let real = revealedSecrets[header.id] {
            dependencies.pasteboard.copy("\(entry.name): \(real)", sensitive: true)
            showCopied(entry.name)
        } else {
            dependencies.pasteboard.copy("\(entry.name): \(entry.value)", sensitive: false)
            showCopied(entry.isSecret
                ? String(localized: "\(entry.name) (masked)", comment: "Network audit toast: a secret header was copied masked. Argument: header name.")
                : entry.name)
        }
    }

    func copyAllHeaders() {
        guard let event = uiState.event else { return }
        let text = storedHeaders(of: event).map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        dependencies.pasteboard.copy(text, sensitive: false)
        showCopied(String(localized: "Headers (secrets masked)", comment: "Network audit toast: every header was copied, secrets masked."))
    }

    func copyBody() {
        guard let text = uiState.body.text else { return }
        dependencies.pasteboard.copy(text, sensitive: false)
        showCopied(String(localized: "Body", comment: "Network audit toast: the body was copied."))
    }

    func copyURL() {
        guard let url = uiState.event?.url else { return }
        dependencies.pasteboard.copy(url, sensitive: false)
        showCopied(String(localized: "Full URL", comment: "Network audit toast: the full (masked) URL was copied."))
    }

    // MARK: - Private

    private func showCopied(_ what: String) {
        uiState.toast = ToastMessage(String(localized: "Copied: \(what)", comment: "Network audit toast: something was copied. Argument: what was copied."), icon: "doc.on.doc")
    }

    private func storedHeaders(of event: NetworkAuditEvent) -> [NetworkAuditHeader] {
        uiState.tab == .request ? event.requestHeaders : event.responseHeaders
    }

    private func rebuild() {
        guard let event = uiState.event else { return }
        let isRequest = uiState.tab == .request
        uiState.headers = storedHeaders(of: event).enumerated().map { index, header in
            let key = NetworkAuditRecorder.secretKey(request: isRequest, index: index)
            let real = uiState.isRevealed ? revealedSecrets[key] : nil
            return NetworkAuditHeaderRow(
                id: key,
                name: header.name,
                displayValue: real ?? header.maskedPreview ?? header.value,
                isSecret: header.isSecret,
                isRevealed: real != nil,
                isAppData: header.isAppData == true
            )
        }
        uiState.body = isRequest ? event.requestBody : event.responseBody
        uiState.whyRows = makeWhyRows(event)
        uiState.summaryRows = makeSummaryRows(event)
    }

    private func makeWhyRows(_ event: NetworkAuditEvent) -> [NetworkAuditInfoRow] {
        let notProvided = String(localized: "Not reported by the caller", comment: "Network audit detail: the call site didn't say which screen made the request.")
        var rows = [
            NetworkAuditInfoRow(label: String(localized: "Origin", comment: "Network audit detail: the screen or flow that made the request."), value: event.origin ?? notProvided)
        ]
        if let parent = event.parentOrigin {
            rows.append(NetworkAuditInfoRow(label: String(localized: "Started By", comment: "Network audit detail: the core operation this request ran inside."), value: parent))
        }
        if let attempt = event.attempt, attempt > 1 {
            rows.append(NetworkAuditInfoRow(
                label: String(localized: "Attempt", comment: "Network audit detail: the attempt number of a retried request."),
                value: String(localized: "\(attempt) (retry)", comment: "Network audit detail: a retried request. Argument: the attempt number.")
            ))
        }
        rows.append(NetworkAuditInfoRow(label: String(localized: "Account Used", comment: "Network audit detail: the account whose credentials were used."), value: event.accountName ?? notProvided))
        rows.append(NetworkAuditInfoRow(label: String(localized: "Purpose", comment: "Network audit detail: why the request was made."), value: event.purpose ?? notProvided))
        if let operation = event.operation {
            rows.append(NetworkAuditInfoRow(label: String(localized: "Core Operation", comment: "Network audit detail: the raw name of the Rust core operation."), value: operation))
        }
        return rows
    }

    private func makeSummaryRows(_ event: NetworkAuditEvent) -> [NetworkAuditInfoRow] {
        var rows: [NetworkAuditInfoRow] = [
            NetworkAuditInfoRow(
                label: String(localized: "Date and Time", comment: "Network audit detail: when the request was made."),
                value: event.date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().second().secondFraction(.fractional(3)))
            )
        ]
        if let duration = event.duration {
            rows.append(NetworkAuditInfoRow(
                label: String(localized: "Duration", comment: "Network audit detail: how long the request took."),
                value: "\(Int((duration * 1000).rounded())) ms"
            ))
        }
        rows.append(NetworkAuditInfoRow(
            label: String(localized: "Sent", comment: "Network audit detail: bytes sent."),
            value: NetworkAuditFormatting.bytes(event.bytesSent)
        ))
        var received = NetworkAuditFormatting.bytes(event.bytesReceived)
        if let wire = event.wireBytesReceived, wire > 0, wire < event.bytesReceived {
            received += " " + String(localized: "(\(NetworkAuditFormatting.bytes(wire)) on the wire)", comment: "Network audit detail: compressed size actually transferred. Argument: byte count.")
        }
        rows.append(NetworkAuditInfoRow(
            label: String(localized: "Received", comment: "Network audit detail: bytes received."),
            value: received
        ))
        if let connection = event.connection {
            rows.append(NetworkAuditInfoRow(
                label: String(localized: "Connection", comment: "Network audit detail: TLS and HTTP versions."),
                value: connection
            ))
        }
        if let error = event.errorDescription {
            rows.append(NetworkAuditInfoRow(
                label: String(localized: "Error", comment: "Network audit detail: the transport error."),
                value: error
            ))
        }
        let retention = dependencies.settings.retention
        let expiry = Calendar.current.date(byAdding: .day, value: retention.days, to: event.date) ?? event.date
        rows.append(NetworkAuditInfoRow(
            label: String(localized: "Removed From the Log", comment: "Network audit detail: when retention deletes this event."),
            value: expiry.formatted(date: .abbreviated, time: .omitted)
        ))
        return rows
    }
}
