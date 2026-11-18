struct AppCategoryModel: Codable, Identifiable, Hashable {
    let id: String
    var subcategories: [AppCategoryModel] = []

    /// Localized App Store name, e.g. `FOOD_AND_DRINK` → "Food & Drink".
    var displayName: String {
        AppStoreCategoryCatalog.displayName(forCategoryId: id)
    }

    /// Localized subcategory name without the parent prefix, e.g. "GAMES_ACTION" → "Action".
    func subcategoryDisplayName(parentId: String) -> String {
        AppStoreCategoryCatalog.displayName(forSubcategoryId: id, parentId: parentId)
    }
}
