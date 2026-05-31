import SwiftUI

// MARK: - Model

/// JSON-driven content for the ``ReleaseNotesView``.
///
/// Example JSON:
/// ```json
/// {
///   "version": "1.2.0",
///   "title": "What's New",
///   "highlights": [
///     {
///       "icon": "sparkles",
///       "color": "blue",
///       "title": "Release Notes",
///       "description": "See what changed every time you update the app."
///     }
///   ]
/// }
/// ```
struct ReleaseNotes: Codable, Equatable {

    /// Marketing version these notes describe (e.g. `"1.2.0"`).
    let version: String

    /// Optional headline. Falls back to a localized default when `nil`.
    let title: String?

    /// The list of highlighted changes shown to the user.
    let highlights: [Highlight]

    struct Highlight: Codable, Equatable, Identifiable {
        let icon: String
        let color: String
        let title: String
        let description: String

        var id: String { icon + title }

        /// Maps the JSON color name to a SwiftUI `Color`. Unknown values
        /// fall back to the app accent color.
        var iconColor: Color {
            switch color.lowercased() {
            case "blue": return .blue
            case "green": return .green
            case "orange": return .orange
            case "red": return .red
            case "purple": return .purple
            case "pink": return .pink
            case "yellow": return .yellow
            case "teal": return .teal
            case "indigo": return .indigo
            case "mint": return .mint
            case "cyan": return .cyan
            case "gray", "grey": return .gray
            case "accent", "accentcolor": return .accentColor
            default: return .accentColor
            }
        }
    }
}

// MARK: - Loading

extension ReleaseNotes {

    /// Decodes ``ReleaseNotes`` from raw JSON data.
    static func decode(from data: Data) throws -> ReleaseNotes {
        try JSONDecoder().decode(ReleaseNotes.self, from: data)
    }

    /// Decodes ``ReleaseNotes`` from a JSON string.
    static func decode(from json: String) throws -> ReleaseNotes {
        guard let data = json.data(using: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return try decode(from: data)
    }

    /// Loads ``ReleaseNotes`` from a bundled JSON file.
    /// - Parameters:
    ///   - name: Resource file name without extension. Defaults to `"ReleaseNotes"`.
    ///   - bundle: Bundle to search. Defaults to `.main`.
    static func load(
        named name: String = "ReleaseNotes",
        in bundle: Bundle = .main
    ) -> ReleaseNotes? {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            Log.print.error("[ReleaseNotes] Missing \(name).json in bundle")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try decode(from: data)
        } catch {
            Log.print.error("[ReleaseNotes] Failed to decode \(name).json: \(error.localizedDescription)")
            return nil
        }
    }
}
