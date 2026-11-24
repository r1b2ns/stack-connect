import Foundation

/// Everything the Audit screens need, injected so ViewModels are tested with
/// an in-memory store, a stub authenticator and a recording pasteboard.
struct NetworkAuditDependencies {
    let store: NetworkAuditStoring
    let settings: NetworkAuditSettingsProviding
    let vault: NetworkAuditSecretSealing
    /// Audits exports. `nil` while capture isn't installed (exports still work).
    let localRecorder: NetworkAuditLocalRecording?
    let authenticator: NetworkAuditOwnerAuthenticating
    let pasteboard: NetworkAuditPasteboardWriting
    let exporter: NetworkAuditExporter
    let now: @Sendable () -> Date

    @MainActor
    static var live: NetworkAuditDependencies {
        NetworkAuditDependencies(
            store: FileNetworkAuditStore.shared,
            settings: NetworkAuditSettings.shared,
            vault: NetworkAuditSecretVault(keychain: KeychainStorable.shared),
            localRecorder: NetworkAuditRecorder.shared,
            authenticator: LocalNetworkAuditOwnerAuthenticator(),
            pasteboard: SystemNetworkAuditPasteboard(),
            exporter: NetworkAuditExporter(),
            now: { Date() }
        )
    }
}
