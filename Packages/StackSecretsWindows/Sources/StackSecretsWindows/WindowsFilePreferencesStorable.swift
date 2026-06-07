import Foundation
import StackProtocols

/// `KeyStorable` backed by a single JSON file on disk — the Windows store for
/// **non-secret preferences** (e.g. the widget configuration under
/// `home.widget.configurations`). It is the Windows counterpart to the iOS
/// `UserDefaultsStorable` preferences role, and is deliberately separate from
/// `WindowsCredentialStorable`, which stays **secrets-only** (Credential
/// Manager). Secrets never land in this plaintext file.
///
/// ## Storage layout
/// All keys live in one JSON object persisted to `<baseDirectory>/<fileName>`:
///
/// - On **Windows** the base directory is `%APPDATA%\StackConnect\` (resolved
///   from the `APPDATA` environment variable) and the file is `prefs.json` by
///   default. The directory is created on demand.
/// - On **non-Windows hosts** the base directory is injectable and defaults to
///   `Application Support/StackConnect/` (via `FileManager`). Tests inject a
///   temp directory. The on-disk semantics are identical to the Windows path,
///   so a write→read round-trip (including restart persistence — a fresh
///   instance pointed at the same directory) is verifiable on the macOS host.
///
/// ## Encoding
/// Each value is stored as a JSON value keyed by its `key`. Primitives map to
/// their natural JSON types; `Data` is base64-encoded (JSON has no binary
/// type), which the `data(forKey:)` reader decodes back. `object`/`setObject`
/// are provided by the `KeyStorable` default extension in `StackProtocols`
/// (they round-trip through `data`/`set`), so any `Codable` value — including
/// `[HomeWidgetConfiguration]` — persists with no extra code here.
///
/// The whole file is rewritten **atomically** on every mutation. The preference
/// payloads are small (a handful of keys), so full-file rewrites are cheaper
/// and simpler than incremental edits, and the atomic replace guarantees the
/// file is never observed half-written across an app restart.
///
/// This package is intentionally kept out of `project.yml`: it ships only with
/// the Windows app, never the iOS target (iOS uses `UserDefaultsStorable`).
public final class WindowsFilePreferencesStorable: KeyStorable {

    private let fileURL: URL
    private let lock = NSLock()

    /// - Parameters:
    ///   - baseDirectory: Directory that holds the prefs file. When `nil`, it is
    ///     resolved per-platform (`%APPDATA%\StackConnect` on Windows, the host
    ///     Application Support directory otherwise). Tests inject a temp dir.
    ///   - fileName: Name of the JSON file inside `baseDirectory`.
    public init(baseDirectory: URL? = nil, fileName: String = "prefs.json") {
        let directory = baseDirectory ?? Self.defaultBaseDirectory()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        self.fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
    }

    // MARK: - Default base directory (per platform)

    private static func defaultBaseDirectory() -> URL {
        #if os(Windows)
        // %APPDATA%\StackConnect — the conventional per-user roaming app-data
        // location on Windows. Fall back to the current directory only if the
        // environment variable is somehow absent.
        let appData = ProcessInfo.processInfo.environment["APPDATA"]
            ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: appData, isDirectory: true)
            .appendingPathComponent("StackConnect", isDirectory: true)
        #else
        // Host fallback: Application Support/StackConnect.
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support.appendingPathComponent("StackConnect", isDirectory: true)
        #endif
    }

    // MARK: - File I/O

    /// Reads the backing file into a `[String: JSONValue]` dictionary. A missing
    /// or unreadable file yields an empty store (treated as "no prefs yet").
    private func load() -> [String: JSONValue] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Atomically rewrites the backing file with the given store.
    private func save(_ store: [String: JSONValue]) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Read (primitives)

    public func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if case let .string(value)? = load()[key] { return value }
        return nil
    }

    public func int(forKey key: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        if case let .int(value)? = load()[key] { return value }
        return nil
    }

    public func double(forKey key: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        switch load()[key] {
        case let .double(value): return value
        case let .int(value): return Double(value)
        default: return nil
        }
    }

    public func bool(forKey key: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        if case let .bool(value)? = load()[key] { return value }
        return nil
    }

    public func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        if case let .data(value)? = load()[key] { return value }
        return nil
    }

    // MARK: - Write (primitives)

    public func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }

        var store = load()

        guard let value else {
            store.removeValue(forKey: key)
            save(store)
            return
        }

        let entry: JSONValue?
        switch value {
        case let v as String: entry = .string(v)
        // `Bool` must be matched before `Int`: on some platforms a `Bool`
        // bridges to `Int`, and we want it stored as a JSON bool.
        case let v as Bool: entry = .bool(v)
        case let v as Int: entry = .int(v)
        case let v as Double: entry = .double(v)
        case let v as Data: entry = .data(v)
        default: entry = nil
        }

        guard let entry else { return }
        store[key] = entry
        save(store)
    }

    // MARK: - Remove

    public func removeObject(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        var store = load()
        store.removeValue(forKey: key)
        save(store)
    }
}

// MARK: - JSONValue

/// A small tagged union for the values this store persists. It gives the JSON
/// file a stable, self-describing shape (so a `Data` value read back as `Data`
/// is never confused with a `String`), while still serializing to plain JSON
/// primitives. `Data` is carried as base64 text since JSON has no binary type.
private enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case data(Data)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum Kind: String, Codable {
        case string, int, double, bool, data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(value):
            try container.encode(Kind.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .int(value):
            try container.encode(Kind.int, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .double(value):
            try container.encode(Kind.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .bool(value):
            try container.encode(Kind.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .data(value):
            try container.encode(Kind.data, forKey: .type)
            // Base64 string — JSON has no native binary representation.
            try container.encode(value.base64EncodedString(), forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .data:
            let base64 = try container.decode(String.self, forKey: .value)
            guard let data = Data(base64Encoded: base64) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Invalid base64 for Data value"
                )
            }
            self = .data(data)
        }
    }
}
