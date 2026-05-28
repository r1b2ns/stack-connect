import Foundation

// MARK: - Model

struct ParsedDevice: Identifiable, Hashable {
    let id = UUID()
    var udid: String
    var name: String
    var platformHint: String?

    /// Loose validation: Apple modern UDID is `8-16` hex (uppercase) or 40-hex legacy.
    var looksValid: Bool {
        let normalized = udid.uppercased()
        let modern = #"^[0-9A-F]{8}-[0-9A-F]{16}$"#
        let legacy = #"^[0-9A-F]{40}$"#
        return normalized.range(of: modern, options: .regularExpression) != nil ||
               normalized.range(of: legacy, options: .regularExpression) != nil
    }
}

// MARK: - Errors

enum DeviceImportError: LocalizedError {
    case emptyFile
    case unreadable
    case invalidPlistShape
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:           return String(localized: "The file is empty.")
        case .unreadable:          return String(localized: "Cannot decode the file contents.")
        case .invalidPlistShape:   return String(localized: "Invalid .deviceids structure: expected a 'Device UDIDs' array.")
        case .parseFailure(let m): return m
        }
    }
}

// MARK: - Parser

enum DeviceImportParser {

    /// Parse the file based on its extension or content sniffing.
    static func parse(data: Data, filename: String) throws -> [ParsedDevice] {
        let lower = filename.lowercased()
        if lower.hasSuffix(".deviceids") || lower.hasSuffix(".plist") || isProbablyPlist(data: data) {
            return try parseDeviceIds(data: data)
        }
        return try parseText(data: data)
    }

    // MARK: - .deviceids (plist)

    static func parseDeviceIds(data: Data) throws -> [ParsedDevice] {
        let raw: Any
        do {
            raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw DeviceImportError.parseFailure(error.localizedDescription)
        }

        guard let root = raw as? [String: Any] else {
            throw DeviceImportError.invalidPlistShape
        }

        // Apple uses the key "Device UDIDs", but tolerate variants like "deviceUDIDs".
        let array =
            (root["Device UDIDs"] as? [[String: Any]]) ??
            (root["DeviceUDIDs"] as? [[String: Any]]) ??
            (root["deviceUDIDs"] as? [[String: Any]])

        guard let entries = array else {
            throw DeviceImportError.invalidPlistShape
        }

        let parsed: [ParsedDevice] = entries.compactMap { entry in
            let udidRaw =
                (entry["deviceIdentifier"] as? String) ??
                (entry["DeviceID"] as? String) ??
                (entry["udid"] as? String)
            let nameRaw =
                (entry["deviceName"] as? String) ??
                (entry["DeviceName"] as? String) ??
                (entry["name"] as? String)
            let platformRaw =
                (entry["devicePlatform"] as? String) ??
                (entry["DevicePlatform"] as? String) ??
                (entry["platform"] as? String)

            guard let udid = udidRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !udid.isEmpty else {
                return nil
            }
            return ParsedDevice(
                udid: udid,
                name: (nameRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                platformHint: normalizePlatform(platformRaw)
            )
        }

        if parsed.isEmpty { throw DeviceImportError.emptyFile }
        return parsed
    }

    // MARK: - .txt (TSV / CSV / whitespace)

    static func parseText(data: Data) throws -> [ParsedDevice] {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw DeviceImportError.unreadable
        }

        var lines = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { throw DeviceImportError.emptyFile }

        // Detect & skip header line.
        if let header = lines.first?.lowercased(),
           header.contains("device id") ||
           header.contains("udid") ||
           header.contains("identifier") ||
           header.contains("device name") {
            lines.removeFirst()
        }

        let rows = lines.map { line -> [String] in
            if line.contains("\t") {
                return line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            if line.contains(",") {
                return line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            // Whitespace separated: first token is UDID, rest is name.
            if let firstSpace = line.firstIndex(where: { $0.isWhitespace }) {
                let udid = String(line[..<firstSpace])
                let rest = line[firstSpace...].trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? [udid] : [udid, rest]
            }
            return [line]
        }

        let parsed: [ParsedDevice] = rows.compactMap { cols in
            guard let udid = cols.first, !udid.isEmpty else { return nil }
            let name = cols.count > 1 ? cols[1] : ""
            let platformRaw = cols.count > 2 ? cols[2] : nil
            return ParsedDevice(
                udid: udid,
                name: name,
                platformHint: normalizePlatform(platformRaw)
            )
        }

        if parsed.isEmpty { throw DeviceImportError.emptyFile }
        return parsed
    }

    // MARK: - Helpers

    private static func isProbablyPlist(data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        let prefix = data.prefix(6)
        // Binary plist (bplist) or XML plist.
        if prefix.starts(with: Array("bplist".utf8)) { return true }
        if prefix.starts(with: Array("<?xml".utf8)) { return true }
        return false
    }

    private static func normalizePlatform(_ raw: String?) -> String? {
        guard let raw = raw?.lowercased() else { return nil }
        if raw.contains("mac") { return "MAC_OS" }
        if raw.contains("ios") || raw.contains("tvos") || raw.contains("watchos") || raw.contains("visionos") {
            return "IOS"
        }
        return nil
    }
}
