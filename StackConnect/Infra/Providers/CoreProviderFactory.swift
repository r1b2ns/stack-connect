import Foundation
import StackCoreRust

/// Builds the Rust core objects an account connection talks to.
///
/// This is the single seam between the App Store Connect / Google Play
/// connections (`AppleAccountConnection`, `GooglePlayAccountConnection`) and the
/// shared Rust core: everything those connections read or write goes through the
/// `Provider` (and its capability handles) returned here. Production uses
/// `RustCoreProviderFactory`; the DEBUG fake data mode installs in-memory
/// providers instead (`BackendEnvironment`, `FakeDataBootstrap`).
protocol CoreProviderMaking: Sendable {

    /// Mirrors the core's `connect(kind:accountId:store:debugLogger:)`.
    func connect(
        kind: ServiceKind,
        accountId: String,
        store: CredentialStore,
        debugLogger: DebugLogger?
    ) throws -> StackCoreRust.Provider

    /// Mirrors the core's `connectWithAccessToken(kind:accountId:tokenProvider:debugLogger:)`:
    /// a provider authorized with the access token `tokenProvider` returns
    /// (Google Play accounts added with "Sign in with Google").
    func connectWithAccessToken(
        kind: ServiceKind,
        accountId: String,
        tokenProvider: AccessTokenProvider,
        debugLogger: DebugLogger?
    ) throws -> StackCoreRust.Provider

    /// Mirrors the core's `connectWithAppleSession(accountId:teamId:sessionStore:debugLogger:)`:
    /// an App Store Connect provider authorized with the Apple ID web session
    /// `sessionStore` holds for `accountId` (accounts added with "Sign in with
    /// Apple ID"), acting for the team `teamId`.
    func connectWithAppleSession(
        accountId: String,
        teamId: UInt64,
        sessionStore: SessionStore,
        debugLogger: DebugLogger?
    ) throws -> StackCoreRust.Provider

    /// Mirrors the core's `makeSyncService(provider:store:accountId:)`.
    func makeSyncService(
        provider: StackCoreRust.Provider,
        store: BlobStore,
        accountId: String
    ) -> StackCoreRust.SyncService

    // MARK: Audited variants

    /// The same three entry points with the core's network audit hook
    /// (`auditSink`, `NetworkAuditCoreSinkFactory.make()`): bound to the
    /// provider and every capability handle it returns. `nil` = not audited.
    func connect(
        kind: ServiceKind,
        accountId: String,
        store: CredentialStore,
        debugLogger: DebugLogger?,
        auditSink: StackCoreRust.NetworkAuditSink?
    ) throws -> StackCoreRust.Provider

    func connectWithAccessToken(
        kind: ServiceKind,
        accountId: String,
        tokenProvider: AccessTokenProvider,
        debugLogger: DebugLogger?,
        auditSink: StackCoreRust.NetworkAuditSink?
    ) throws -> StackCoreRust.Provider

    func connectWithAppleSession(
        accountId: String,
        teamId: UInt64,
        sessionStore: SessionStore,
        debugLogger: DebugLogger?,
        auditSink: StackCoreRust.NetworkAuditSink?
    ) throws -> StackCoreRust.Provider
}

/// Fakes and test doubles make no network calls: the audited variants fall
/// back to the plain ones and drop the sink.
extension CoreProviderMaking {
    func connect(
        kind: ServiceKind,
        accountId: String,
        store: CredentialStore,
        debugLogger: DebugLogger?,
        auditSink: StackCoreRust.NetworkAuditSink?
    ) throws -> StackCoreRust.Provider {
        try connect(kind: kind, accountId: accountId, store: store, debugLogger: debugLogger)
    }

    func connectWithAccessToken(
        kind: ServiceKind,
        accountId: String,
        tokenProvider: AccessTokenProvider,
        debugLogger: DebugLogger?,
        auditSink: StackCoreRust.NetworkAuditSink?
    ) throws -> StackCoreRust.Provider {
        try connectWithAccessToken(kind: kind, accountId: accountId, tokenProvider: tokenProvider, debugLogger: debugLogger)
    }

    func connectWithAppleSession(
        accountId: String,
        teamId: UInt64,
        sessionStore: SessionStore,
        debugLogger: DebugLogger?,
        auditSink: StackCoreRust.NetworkAuditSink?
    ) throws -> StackCoreRust.Provider {
        try connectWithAppleSession(accountId: accountId, teamId: teamId, sessionStore: sessionStore, debugLogger: debugLogger)
    }
}

/// The real Rust core: forwards to the UniFFI facade functions.
struct RustCoreProviderFactory: CoreProviderMaking {

    func connect(
        kind: ServiceKind,
        accountId: String,
        store: CredentialStore,
        debugLogger: DebugLogger?
    ) throws -> StackCoreRust.Provider {
        try StackCoreRust.connect(kind: kind, accountId: accountId, store: store, debugLogger: debugLogger)
    }

    func connectWithAccessToken(
        kind: ServiceKind,
        accountId: String,
        tokenProvider: AccessTokenProvider,
        debugLogger: DebugLogger?
    ) throws -> StackCoreRust.Provider {
        try StackCoreRust.connectWithAccessToken(kind: kind, accountId: accountId, tokenProvider: tokenProvider, debugLogger: debugLogger)
    }

    func connectWithAppleSession(
        accountId: String,
        teamId: UInt64,
        sessionStore: SessionStore,
        debugLogger: DebugLogger?
    ) throws -> StackCoreRust.Provider {
        try StackCoreRust.connectWithAppleSession(accountId: accountId, teamId: teamId, sessionStore: sessionStore, debugLogger: debugLogger)
    }

    func makeSyncService(
        provider: StackCoreRust.Provider,
        store: BlobStore,
        accountId: String
    ) -> StackCoreRust.SyncService {
        StackCoreRust.makeSyncService(provider: provider, store: store, accountId: accountId)
    }

    func connect(
        kind: ServiceKind,
        accountId: String,
        store: CredentialStore,
        debugLogger: DebugLogger?,
        auditSink: StackCoreRust.NetworkAuditSink?
    ) throws -> StackCoreRust.Provider {
        try StackCoreRust.connect(kind: kind, accountId: accountId, store: store, debugLogger: debugLogger, auditSink: auditSink)
    }

    func connectWithAccessToken(
        kind: ServiceKind,
        accountId: String,
        tokenProvider: AccessTokenProvider,
        debugLogger: DebugLogger?,
        auditSink: StackCoreRust.NetworkAuditSink?
    ) throws -> StackCoreRust.Provider {
        try StackCoreRust.connectWithAccessToken(kind: kind, accountId: accountId, tokenProvider: tokenProvider, debugLogger: debugLogger, auditSink: auditSink)
    }

    func connectWithAppleSession(
        accountId: String,
        teamId: UInt64,
        sessionStore: SessionStore,
        debugLogger: DebugLogger?,
        auditSink: StackCoreRust.NetworkAuditSink?
    ) throws -> StackCoreRust.Provider {
        try StackCoreRust.connectWithAppleSession(accountId: accountId, teamId: teamId, sessionStore: sessionStore, debugLogger: debugLogger, auditSink: auditSink)
    }
}
