import Foundation
import StackProtocols
import StackCoreRust

/// Subset of `GooglePlayAccountConnection` the Google Play screens use. Carved out
/// so ViewModels can be unit-tested with a mock connection (no keychain, no
/// network, no Rust core).
protocol GooglePlayAccountConnecting: Sendable {
    /// Token exchange + a 1-item Play Developer Reporting `apps:search`. Success
    /// means the key works and the Reporting API is enabled — it does NOT
    /// guarantee any app is visible yet (Play Console access can take hours to
    /// propagate).
    func validateCredentials() async throws

    /// Every app the service account can see. For Play `id == bundleId ==`
    /// package name and `platform == "ANDROID"`.
    func fetchApps() async throws -> [StackProtocols.AppInfo]
}

/// Google Play account connection backed by the shared Rust core (plan D1),
/// mirroring `AppleAccountConnection`.
///
/// The stored `GooglePlayCredentials` keep the whole service-account JSON (D2);
/// it is parsed into `GooglePlayServiceAccount` when the core provider is first
/// built. Errors are surfaced unchanged (`GooglePlayServiceAccount.ParseError`,
/// `StackError`, `OfflineError`) — callers turn them into copy with
/// `GooglePlayErrorTranslator`.
final class GooglePlayAccountConnection: AccountConnectionProtocol, GooglePlayAccountConnecting, @unchecked Sendable {

    private let credentials: GooglePlayCredentials

    /// Resolves feature flags (e.g. `useRustCoreDebugLogging`). Injected for testability.
    private let featureFlags: FeatureFlags

    /// Synchronous connectivity probe. Unlike App Store Connect there is no
    /// offline-capable read here — every call is a live Google request — so
    /// both `validateCredentials()` and `fetchApps()` fail fast offline (callers
    /// keep their cache) instead of waiting for a network timeout.
    private let connectivity: ConnectivityProviding

    /// Serialises the lazy build of `rustProvider`: `@unchecked Sendable` means
    /// two tasks may ask for the provider at once.
    private let lock = NSLock()

    /// Lazily-built Rust core provider, reused across calls on this connection.
    private var rustProvider: StackCoreRust.Provider?

    init(
        credentials: GooglePlayCredentials,
        featureFlags: FeatureFlags = .shared,
        connectivity: ConnectivityProviding = ConnectivityMonitor.shared
    ) {
        self.credentials = credentials
        self.featureFlags = featureFlags
        self.connectivity = connectivity
    }

    /// Throws `OfflineError.noConnection` when the device is offline so network
    /// calls fail fast (and with friendly copy).
    private func requireOnline() throws {
        if !connectivity.isCurrentlyOnline() {
            throw OfflineError.noConnection
        }
    }

    // MARK: - AccountConnectionProtocol

    func validateCredentials() async throws {
        try requireOnline()
        let provider = try rustCoreProvider()
        try await callRustCore { try await provider.validate() }
        Log.print.info("[GooglePlay] Credentials validated successfully (Rust core)")
    }

    func fetchApps() async throws -> [StackProtocols.AppInfo] {
        try requireOnline()
        let provider = try rustCoreProvider()
        let coreApps = try await callRustCore { try await provider.fetchApps() }
        let apps = coreApps.map { app in
            StackProtocols.AppInfo(
                id: app.id,
                name: app.name,
                bundleId: app.bundleId,
                platform: app.platform
            )
        }
        Log.print.info("[GooglePlay] Fetched \(apps.count) apps (Rust core)")
        return apps
    }

    func disconnect() {
        lock.withLock { rustProvider = nil }
        Log.print.info("[GooglePlay] Disconnected")
    }

    // MARK: - Rust core

    /// Lazily builds and caches the Rust core `Provider` for Google Play.
    ///
    /// `connect(...)` is synchronous and offline: it reads the three secrets via
    /// `GooglePlayCredentialStore` and parses the RSA key eagerly, so a bad key
    /// throws `StackError.InvalidCredentials` here. The `accountId` is the
    /// service account's `client_email` (plan D3) — a stable, credential-derived
    /// identifier the read-only store ignores.
    private func rustCoreProvider() throws -> StackCoreRust.Provider {
        try lock.withLock {
            if let rustProvider {
                return rustProvider
            }
            let serviceAccount = try GooglePlayServiceAccount(credentials: credentials)
            do {
                let provider = try connect(
                    kind: .googlePlay,
                    accountId: serviceAccount.clientEmail,
                    store: GooglePlayCredentialStore(serviceAccount: serviceAccount),
                    debugLogger: featureFlags.isEnabled(.useRustCoreDebugLogging) ? RustCoreDebugLogger() : nil
                )
                rustProvider = provider
                return provider
            } catch let error as StackError {
                throw translate(error)
            }
        }
    }

    /// Runs a Rust core async call, routing `StackError` through `translate`.
    private func callRustCore<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as StackError {
            throw translate(error)
        }
    }

    /// Logs a Rust-core error at the boundary and preserves the typed error, so
    /// `GooglePlayErrorTranslator` can still map it to user-facing copy.
    private func translate(_ error: StackError) -> Error {
        Log.print.error("[GooglePlay] Rust core error: \(error.localizedDescription)")
        return error
    }
}
