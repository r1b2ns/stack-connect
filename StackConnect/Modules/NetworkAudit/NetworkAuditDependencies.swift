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
    /// StackConnect's own identifiers, hidden on read too (events stored
    /// before the masking).
    var appIdentity: NetworkAuditAppIdentity = .current

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

// MARK: - App-owned values copy

/// The explanation shown wherever values that belong to StackConnect itself
/// (its bundle ID, Firebase project, keys and tokens) are hidden.
enum NetworkAuditAppSecretCopy {

    static var badge: String {
        String(localized: "APP SECRET", comment: "Network audit: badge of a secret that belongs to StackConnect's own telemetry (Firebase).")
    }

    static var dataBadge: String {
        String(localized: "APP DATA", comment: "Network audit: badge of a value that carried StackConnect's own identifiers (bundle ID, Firebase project).")
    }

    static var title: String {
        String(localized: "Hidden: Belongs to StackConnect", comment: "Network audit: title of the card explaining hidden app-owned values.")
    }

    static var message: String {
        String(localized: "Some values identify or protect StackConnect itself (its bundle ID, Firebase project, keys and tokens), not your data. They're never shown, copied or exported, not even with Face ID. Everything about you and your accounts stays visible.", comment: "Network audit: why app-owned values are hidden.")
    }

    static var exportNote: String {
        String(localized: "This is StackConnect's own telemetry: its identifiers, keys and tokens stay hidden in every format, cURL included.", comment: "Network audit export: note for an app telemetry event.")
    }

    static var tokenSubtitle: String {
        String(localized: "StackConnect's telemetry key · never included", comment: "Network audit export: subtitle of the disabled token switch for app telemetry.")
    }

    static var maskedListItem: String {
        String(localized: "StackConnect's own identifiers, keys and tokens (bundle ID, Firebase project)", comment: "Network audit export: masked secret.")
    }
}
