import Foundation
import StackProtocols
import StackStorageSQLite
import StackSecretsWindows

/// The platform-wired services the app runs on. The Windows counterpart to the
/// iOS bootstrap in `StackConnectApp` (which builds a `ModelContainer` +
/// `SwiftDataStorable` and a `KeychainStorable`): here the cross-platform SQLite
/// backend and the Windows Credential Manager take their place.
struct AppEnvironment {
    let storage: PersistentStorable
    let secrets: KeyStorable
    let storePath: String
}

/// Phase 4 · B2 — per-platform bootstrap for the Windows app.
enum Bootstrap {

    /// Opens the SQLite store at `%APPDATA%\StackConnect\store.sqlite` and the
    /// Credential Manager-backed secret store. Throws if the data directory or
    /// database cannot be created/opened.
    static func makeEnvironment() throws -> AppEnvironment {
        let storePath = try AppPaths.storeDatabasePath()
        let storage = try SQLitePersistentStorable(path: storePath)
        let secrets = WindowsCredentialStorable()
        return AppEnvironment(storage: storage, secrets: secrets, storePath: storePath)
    }
}
