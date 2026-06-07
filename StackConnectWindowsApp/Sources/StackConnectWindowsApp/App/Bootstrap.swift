import Foundation
import StackProtocols
import StackStorageSQLite
import StackSecretsWindows

// Phase 4 · B2 — per-platform bootstrap for the Windows GUI app.
//
// The Windows counterpart to the iOS bootstrap in `StackConnectApp` (which
// builds a SwiftData `ModelContainer` + `KeychainStorable`): here the
// cross-platform SQLite backend takes the place of SwiftData, and a file-based
// preferences store (T-A12) holds the non-secret Home prefs (widget config).
// The Windows Credential Manager stays secrets-only and is not needed by the
// Home shell, so it is intentionally left out of this environment for now.

/// The platform-wired services the Home runs on.
struct AppEnvironment {
    /// Cross-platform SQLite app store (`%APPDATA%\StackConnect\store.sqlite`).
    let storage: PersistentStorable
    /// File-based non-secret preferences (`%APPDATA%\StackConnect\prefs.json`),
    /// used by the core `HomeViewModel` to persist widget configuration (D1).
    let preferences: KeyStorable
    /// Resolved path of the SQLite store (for diagnostics).
    let storePath: String
}

enum Bootstrap {

    /// Opens the SQLite store and the file-based preferences store. Throws if the
    /// data directory or database cannot be created/opened.
    static func makeEnvironment() throws -> AppEnvironment {
        let storePath = try AppPaths.storeDatabasePath()
        let storage = try SQLitePersistentStorable(path: storePath)
        let preferences = WindowsFilePreferencesStorable()
        return AppEnvironment(storage: storage, preferences: preferences, storePath: storePath)
    }
}
