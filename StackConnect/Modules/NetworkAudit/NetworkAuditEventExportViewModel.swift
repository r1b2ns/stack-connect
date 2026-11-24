import Foundation

// MARK: - Protocol

@MainActor
protocol NetworkAuditEventExportViewModelProtocol: ObservableObject {
    var uiState: NetworkAuditEventExportUiState { get set }
    func load() async
    func selectFormat(_ format: NetworkAuditEventFormat)
    func setIncludeBody(_ enabled: Bool)
    /// Turning ON asks for Face ID and only works for a short-lived token
    /// that is still valid; turning OFF needs nothing.
    func setIncludeRealToken(_ enabled: Bool) async
    func copy()
    func share()
    func shareDidFinish()
}

// MARK: - UiState

struct NetworkAuditEventExportUiState {
    var event: NetworkAuditEvent?
    var format: NetworkAuditEventFormat = .curl
    var includeBody = true
    var includesRealToken = false
    var tokenInclusion: NetworkAuditTokenInclusion = .notApplicable
    var preview = ""
    var secretNote = ""
    var shareItem: NetworkAuditShareItem?
    var toast: ToastMessage?

    var isCurl: Bool { format == .curl }
    /// The "Include real token" switch is shown for cURL when the request had
    /// an `Authorization` header, and enabled while the token is includable.
    var showsTokenToggle: Bool { isCurl && tokenInclusion != .notApplicable }
    var canToggleToken: Bool { tokenInclusion.canInclude || includesRealToken }
}

// MARK: - Implementation

@MainActor
final class NetworkAuditEventExportViewModel: NetworkAuditEventExportViewModelProtocol {

    @Published var uiState = NetworkAuditEventExportUiState()

    private let summary: NetworkAuditEventSummary
    private let dependencies: NetworkAuditDependencies
    /// The decrypted `Authorization` value, in memory only while the toggle is ON.
    private var realAuthorization: String?

    init(summary: NetworkAuditEventSummary, dependencies: NetworkAuditDependencies? = nil) {
        self.summary = summary
        self.dependencies = dependencies ?? .live
    }

    func load() async {
        uiState.event = await dependencies.store.event(for: summary)
        refresh()
    }

    func selectFormat(_ format: NetworkAuditEventFormat) {
        uiState.format = format
        if format != .curl {
            dropToken()
        }
        refresh()
    }

    func setIncludeBody(_ enabled: Bool) {
        uiState.includeBody = enabled
        refresh()
    }

    func setIncludeRealToken(_ enabled: Bool) async {
        guard enabled else {
            dropToken()
            refresh()
            return
        }
        refresh()
        guard uiState.isCurl, uiState.tokenInclusion.canInclude,
              let event = uiState.event, let sealed = event.sealedSecrets,
              let index = event.requestHeaders.firstIndex(where: { $0.name.caseInsensitiveCompare("Authorization") == .orderedSame }) else {
            return
        }
        let reason = String(localized: "Include the real token in the cURL command.", comment: "Face ID reason: exporting a recorded token in a cURL command.")
        guard await dependencies.authenticator.authenticate(reason: reason),
              let secrets = dependencies.vault.open(sealed),
              let value = secrets[NetworkAuditRecorder.secretKey(request: true, index: index)] else {
            refresh()
            return
        }
        realAuthorization = value
        uiState.includesRealToken = true
        uiState.toast = ToastMessage(String(localized: "Face ID confirmed", comment: "Network audit toast: Face ID was confirmed to include the token."), icon: "faceid")
        refresh()
    }

    func copy() {
        refresh()
        guard let event = uiState.event else { return }
        let text = output(for: event)
        // Local-only, expires in 2 minutes: the clipboard may carry a token.
        dependencies.pasteboard.copy(text, sensitive: true)
        record(event, text: text, action: .copied)
        uiState.toast = ToastMessage(
            uiState.includesRealToken
                ? String(localized: "Copied with token · clears in 2 min", comment: "Network audit toast: a cURL with a real token was copied.")
                : String(localized: "Copied (masked)", comment: "Network audit toast: a masked export was copied."),
            icon: "doc.on.doc"
        )
    }

    func share() {
        refresh()
        guard let event = uiState.event else { return }
        let text = output(for: event)
        let name = "StackConnect-\(event.method)-\(NetworkAuditExportViewModel.fileStamp(event.date)).\(uiState.format.fileExtension)"
        guard let url = NetworkAuditShareFile.write(text, name: name) else { return }
        uiState.shareItem = NetworkAuditShareItem(fileURL: url)
        record(event, text: text, action: .shared)
    }

    func shareDidFinish() {
        NetworkAuditShareFile.remove(uiState.shareItem)
        uiState.shareItem = nil
    }

    // MARK: - Private

    private func dropToken() {
        realAuthorization = nil
        uiState.includesRealToken = false
    }

    /// Re-evaluates the token's validity (time passes while the sheet is
    /// open: an expired token is dropped) and rebuilds the preview.
    private func refresh() {
        guard let event = uiState.event else { return }
        uiState.tokenInclusion = NetworkAuditTokenInclusion.evaluate(event, now: dependencies.now())
        if uiState.includesRealToken, !uiState.tokenInclusion.canInclude || !uiState.isCurl {
            dropToken()
        }
        uiState.preview = preview(for: event)
        uiState.secretNote = secretNote(for: event)
    }

    private func output(for event: NetworkAuditEvent) -> String {
        dependencies.exporter.single(
            event,
            format: uiState.format,
            includeBody: uiState.includeBody,
            realAuthorization: uiState.includesRealToken && uiState.isCurl ? realAuthorization : nil
        )
    }

    /// Like the output, but a real token only shows its first characters.
    private func preview(for event: NetworkAuditEvent) -> String {
        var shortened: String?
        if uiState.includesRealToken, let realAuthorization,
           let (scheme, credential) = NetworkAuditSecretMasker.splitScheme(realAuthorization) {
            shortened = "\(scheme) \(credential.prefix(12))…"
        }
        return dependencies.exporter.single(
            event,
            format: uiState.format,
            includeBody: uiState.includeBody,
            realAuthorization: shortened
        )
    }

    private func secretNote(for event: NetworkAuditEvent) -> String {
        if uiState.includesRealToken {
            return String(localized: "This command carries a valid token: anyone with the text acts with your API key's permissions until it expires. Don't paste it in public issues, chats or support tickets.", comment: "Network audit: warning when a cURL carries a real token.")
        }
        if uiState.isCurl, uiState.tokenInclusion != .notApplicable {
            return String(localized: "The token is masked. The command returns 401 until you put a valid token in.", comment: "Network audit: note for a masked cURL.")
        }
        let count = event.requestHeaders.filter(\.isSecret).count + event.responseHeaders.filter(\.isSecret).count
        if count == 0 {
            return String(localized: "No secret headers in this event. Secrets in the URL and bodies are masked.", comment: "Network audit: note when the event has no secret header.")
        }
        return String(localized: "\(count) secrets will be masked. Only cURL can carry the real token.", comment: "Network audit: note about masked secrets. Argument: count of secret headers.")
    }

    private func record(_ event: NetworkAuditEvent, text: String, action: NetworkAuditExportRecord.Action) {
        dependencies.localRecorder?.recordExport(NetworkAuditExportRecord(
            formatName: uiState.format.title,
            subject: "\(event.method) \(event.host)\(event.kind == .http ? event.path.split(separator: "?").first.map(String.init) ?? "" : "")",
            action: action,
            includesRealToken: uiState.includesRealToken && uiState.isCurl,
            byteCount: Int64(text.utf8.count)
        ))
    }
}
