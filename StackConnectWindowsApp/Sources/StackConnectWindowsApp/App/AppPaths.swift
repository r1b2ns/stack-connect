import Foundation

/// Resolves the on-disk locations the Windows app uses for its data.
///
/// On Windows the data lives under `%APPDATA%\StackConnect`; on the host
/// (for build/smoke runs) it falls back to Application Support, then `$HOME`.
///
/// Mirrors the headless `StackConnectWindows` package's `AppPaths` (that target
/// is an executable and can't be imported as a library, so the small amount of
/// path logic is intentionally duplicated here).
enum AppPaths {

    enum PathError: Error, CustomStringConvertible {
        case noBaseDirectory
        case createFailed(String)

        var description: String {
            switch self {
            case .noBaseDirectory:
                return "could not resolve a base directory for app data"
            case .createFailed(let message):
                return "failed to create app data directory: \(message)"
            }
        }
    }

    static let appFolderName = "StackConnect"

    private static var separator: String {
        #if os(Windows)
        return "\\"
        #else
        return "/"
        #endif
    }

    /// `%APPDATA%\StackConnect` (Windows) or its host equivalent, created if needed.
    static func dataDirectory() throws -> String {
        let environment = ProcessInfo.processInfo.environment

        let base: String?
        #if os(Windows)
        base = environment["APPDATA"]
        #else
        base = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first
            ?? environment["HOME"].map { $0 + "/.local/share" }
        #endif

        guard let base, !base.isEmpty else { throw PathError.noBaseDirectory }

        let directory = base + separator + appFolderName
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            throw PathError.createFailed(error.localizedDescription)
        }
        return directory
    }

    /// `%APPDATA%\StackConnect\store.sqlite`.
    static func storeDatabasePath() throws -> String {
        try dataDirectory() + separator + "store.sqlite"
    }
}
