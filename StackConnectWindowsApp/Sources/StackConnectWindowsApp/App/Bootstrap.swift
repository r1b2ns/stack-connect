import Foundation
import StackProtocols
import StackStorageSQLite
import StackSecretsWindows

// Phase 4 · B2 — per-platform bootstrap for the Windows GUI app.
//
// The Windows counterpart to the iOS bootstrap in `StackConnectApp` (which
// builds a SwiftData `ModelContainer` + `KeychainStorable`): here the
// cross-platform SQLite backend takes the place of SwiftData, a file-based
// preferences store (T-A12) holds the non-secret Home prefs (widget config),
// and the Windows Credential Manager provides encrypted secret storage for
// API keys, p8 keys, and other credentials.

/// The platform-wired services the Home runs on.
struct AppEnvironment {
    /// Cross-platform SQLite app store (`%APPDATA%\StackConnect\store.sqlite`).
    let storage: PersistentStorable
    /// File-based non-secret preferences (`%APPDATA%\StackConnect\prefs.json`),
    /// used by the core `HomeViewModel` to persist widget configuration (D1).
    let preferences: KeyStorable
    /// Encrypted credential store backed by Windows Credential Manager,
    /// used for saving/loading API keys, p8 keys, and other secrets.
    let secrets: KeyStorable
    /// Resolved path of the SQLite store (for diagnostics).
    let storePath: String
}

enum Bootstrap {

    /// Opens the SQLite store, the file-based preferences store, and the
    /// encrypted credential store. Throws if the data directory or database
    /// cannot be created/opened.
    static func makeEnvironment() throws -> AppEnvironment {
        let storePath = try AppPaths.storeDatabasePath()
        let storage = try SQLitePersistentStorable(path: storePath)
        let preferences = WindowsFilePreferencesStorable()
        let secrets = WindowsCredentialStorable()
        return AppEnvironment(
            storage: storage,
            preferences: preferences,
            secrets: secrets,
            storePath: storePath
        )
    }
}
