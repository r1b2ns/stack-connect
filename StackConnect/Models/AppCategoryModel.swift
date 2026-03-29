struct AppCategoryModel: Codable, Identifiable, Hashable {
    let id: String
    var subcategories: [AppCategoryModel] = []

    /// Human-readable name: replaces underscores with spaces and capitalizes each word.
    var displayName: String {
        id.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    /// Display name for a subcategory — strips the parent prefix, e.g. "GAMES_ACTION" → "Action".
    func subcategoryDisplayName(parentId: String) -> String {
        let prefix = parentId + "_"
        if id.hasPrefix(prefix) {
            let suffix = String(id.dropFirst(prefix.count))
            return suffix.replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
        return displayName
    }
}
