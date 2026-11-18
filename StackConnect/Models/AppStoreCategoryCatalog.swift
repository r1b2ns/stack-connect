import Foundation

/// The App Store Connect category catalog (`appCategories` ids) and the
/// human-readable, localized names the App Store shows for each of them.
///
/// ASC ids are SCREAMING_SNAKE_CASE (`FOOD_AND_DRINK`, `GAMES_ROLE_PLAYING`) and
/// mechanically title-casing them produces wrong labels ("Food And Drink"), so
/// every known id is mapped explicitly. Unknown ids (new categories Apple may add)
/// fall back to a humanized form that still renders `_AND_` as `&`.
enum AppStoreCategoryCatalog {

    /// Every top-level ASC category with its subcategory ids, in App Store order.
    /// Used to guarantee the category picker always has a tag for a valid
    /// selection, even when the API omits a category or the fetch fails.
    static let all: [AppCategoryModel] = [
        AppCategoryModel(id: "BOOKS"),
        AppCategoryModel(id: "BUSINESS"),
        AppCategoryModel(id: "DEVELOPER_TOOLS"),
        AppCategoryModel(id: "EDUCATION"),
        AppCategoryModel(id: "ENTERTAINMENT"),
        AppCategoryModel(id: "FINANCE"),
        AppCategoryModel(id: "FOOD_AND_DRINK"),
        AppCategoryModel(id: "GAMES", subcategories: gameSubcategoryIds.map { AppCategoryModel(id: $0) }),
        AppCategoryModel(id: "GRAPHICS_AND_DESIGN"),
        AppCategoryModel(id: "HEALTH_AND_FITNESS"),
        AppCategoryModel(id: "LIFESTYLE"),
        AppCategoryModel(id: "MAGAZINES_AND_NEWSPAPERS"),
        AppCategoryModel(id: "MEDICAL"),
        AppCategoryModel(id: "MUSIC"),
        AppCategoryModel(id: "NAVIGATION"),
        AppCategoryModel(id: "NEWS"),
        AppCategoryModel(id: "PHOTO_AND_VIDEO"),
        AppCategoryModel(id: "PRODUCTIVITY"),
        AppCategoryModel(id: "REFERENCE"),
        AppCategoryModel(id: "SHOPPING"),
        AppCategoryModel(id: "SOCIAL_NETWORKING"),
        AppCategoryModel(id: "SPORTS"),
        AppCategoryModel(id: "STICKERS", subcategories: stickerSubcategoryIds.map { AppCategoryModel(id: $0) }),
        AppCategoryModel(id: "TRAVEL"),
        AppCategoryModel(id: "UTILITIES"),
        AppCategoryModel(id: "WEATHER")
    ]

    static let gameSubcategoryIds: [String] = [
        "GAMES_ACTION", "GAMES_ADVENTURE", "GAMES_BOARD", "GAMES_CARD", "GAMES_CASINO",
        "GAMES_CASUAL", "GAMES_FAMILY", "GAMES_MUSIC", "GAMES_PUZZLE", "GAMES_RACING",
        "GAMES_ROLE_PLAYING", "GAMES_SIMULATION", "GAMES_SPORTS", "GAMES_STRATEGY",
        "GAMES_TRIVIA", "GAMES_WORD"
    ]

    static let stickerSubcategoryIds: [String] = [
        "STICKERS_ANIMALS", "STICKERS_ART", "STICKERS_BIRTHDAYS", "STICKERS_CELEBRITIES",
        "STICKERS_CHARACTERS", "STICKERS_EATING_AND_DRINKING", "STICKERS_EMOJI_AND_EXPRESSIONS",
        "STICKERS_FASHION", "STICKERS_GAMING", "STICKERS_KIDS_AND_FAMILY",
        "STICKERS_MOVIES_AND_TV", "STICKERS_MUSIC", "STICKERS_PEOPLE",
        "STICKERS_PLACES_AND_OBJECTS", "STICKERS_SPORTS_AND_ACTIVITIES"
    ]

    /// Localized App Store name for a top-level category id, e.g.
    /// `FOOD_AND_DRINK` → "Food & Drink".
    static func displayName(forCategoryId id: String) -> String {
        switch id {
        case "BOOKS":                    return String(localized: "Books", comment: "App Store category")
        case "BUSINESS":                 return String(localized: "Business", comment: "App Store category")
        case "DEVELOPER_TOOLS":          return String(localized: "Developer Tools", comment: "App Store category")
        case "EDUCATION":                return String(localized: "Education", comment: "App Store category")
        case "ENTERTAINMENT":            return String(localized: "Entertainment", comment: "App Store category")
        case "FINANCE":                  return String(localized: "Finance", comment: "App Store category")
        case "FOOD_AND_DRINK":           return String(localized: "Food & Drink", comment: "App Store category")
        case "GAMES":                    return String(localized: "Games", comment: "App Store category")
        case "GRAPHICS_AND_DESIGN":      return String(localized: "Graphics & Design", comment: "App Store category")
        case "HEALTH_AND_FITNESS":       return String(localized: "Health & Fitness", comment: "App Store category")
        case "LIFESTYLE":                return String(localized: "Lifestyle", comment: "App Store category")
        case "MAGAZINES_AND_NEWSPAPERS": return String(localized: "Magazines & Newspapers", comment: "App Store category")
        case "MEDICAL":                  return String(localized: "Medical", comment: "App Store category")
        case "MUSIC":                    return String(localized: "Music", comment: "App Store category")
        case "NAVIGATION":               return String(localized: "Navigation", comment: "App Store category")
        case "NEWS":                     return String(localized: "News", comment: "App Store category")
        case "PHOTO_AND_VIDEO":          return String(localized: "Photo & Video", comment: "App Store category")
        case "PRODUCTIVITY":             return String(localized: "Productivity", comment: "App Store category")
        case "REFERENCE":                return String(localized: "Reference", comment: "App Store category")
        case "SHOPPING":                 return String(localized: "Shopping", comment: "App Store category")
        case "SOCIAL_NETWORKING":        return String(localized: "Social Networking", comment: "App Store category")
        case "SPORTS":                   return String(localized: "Sports", comment: "App Store category")
        case "STICKERS":                 return String(localized: "Stickers", comment: "App Store category")
        case "TRAVEL":                   return String(localized: "Travel", comment: "App Store category")
        case "UTILITIES":                return String(localized: "Utilities", comment: "App Store category")
        case "WEATHER":                  return String(localized: "Weather", comment: "App Store category")
        default:                         return humanize(id)
        }
    }

    /// Localized App Store name for a subcategory id. The parent prefix is never
    /// shown: `GAMES_ROLE_PLAYING` → "Role Playing".
    static func displayName(forSubcategoryId id: String, parentId: String? = nil) -> String {
        switch id {
        case "GAMES_ACTION":                   return String(localized: "Action", comment: "App Store games subcategory")
        case "GAMES_ADVENTURE":                return String(localized: "Adventure", comment: "App Store games subcategory")
        case "GAMES_BOARD":                    return String(localized: "Board", comment: "App Store games subcategory")
        case "GAMES_CARD":                     return String(localized: "Card", comment: "App Store games subcategory")
        case "GAMES_CASINO":                   return String(localized: "Casino", comment: "App Store games subcategory")
        case "GAMES_CASUAL":                   return String(localized: "Casual", comment: "App Store games subcategory")
        case "GAMES_FAMILY":                   return String(localized: "Family", comment: "App Store games subcategory")
        case "GAMES_MUSIC":                    return String(localized: "Music", comment: "App Store category")
        case "GAMES_PUZZLE":                   return String(localized: "Puzzle", comment: "App Store games subcategory")
        case "GAMES_RACING":                   return String(localized: "Racing", comment: "App Store games subcategory")
        case "GAMES_ROLE_PLAYING":             return String(localized: "Role Playing", comment: "App Store games subcategory")
        case "GAMES_SIMULATION":               return String(localized: "Simulation", comment: "App Store games subcategory")
        case "GAMES_SPORTS":                   return String(localized: "Sports", comment: "App Store category")
        case "GAMES_STRATEGY":                 return String(localized: "Strategy", comment: "App Store games subcategory")
        case "GAMES_TRIVIA":                   return String(localized: "Trivia", comment: "App Store games subcategory")
        case "GAMES_WORD":                     return String(localized: "Word", comment: "App Store games subcategory")
        case "STICKERS_ANIMALS":               return String(localized: "Animals", comment: "App Store stickers subcategory")
        case "STICKERS_ART":                   return String(localized: "Art", comment: "App Store stickers subcategory")
        case "STICKERS_BIRTHDAYS":             return String(localized: "Birthdays", comment: "App Store stickers subcategory")
        case "STICKERS_CELEBRITIES":           return String(localized: "Celebrities", comment: "App Store stickers subcategory")
        case "STICKERS_CHARACTERS":            return String(localized: "Characters", comment: "App Store stickers subcategory")
        case "STICKERS_EATING_AND_DRINKING":   return String(localized: "Eating & Drinking", comment: "App Store stickers subcategory")
        case "STICKERS_EMOJI_AND_EXPRESSIONS": return String(localized: "Emoji & Expressions", comment: "App Store stickers subcategory")
        case "STICKERS_FASHION":               return String(localized: "Fashion", comment: "App Store stickers subcategory")
        case "STICKERS_GAMING":                return String(localized: "Gaming", comment: "App Store stickers subcategory")
        case "STICKERS_KIDS_AND_FAMILY":       return String(localized: "Kids & Family", comment: "App Store stickers subcategory")
        case "STICKERS_MOVIES_AND_TV":         return String(localized: "Movies & TV", comment: "App Store stickers subcategory")
        case "STICKERS_MUSIC":                 return String(localized: "Music", comment: "App Store category")
        case "STICKERS_PEOPLE":                return String(localized: "People", comment: "App Store stickers subcategory")
        case "STICKERS_PLACES_AND_OBJECTS":    return String(localized: "Places & Objects", comment: "App Store stickers subcategory")
        case "STICKERS_SPORTS_AND_ACTIVITIES": return String(localized: "Sports & Activities", comment: "App Store stickers subcategory")
        default:
            let prefix = (parentId ?? id.components(separatedBy: "_").first ?? "") + "_"
            if !prefix.isEmpty, prefix != "_", id.hasPrefix(prefix), id.count > prefix.count {
                return humanize(String(id.dropFirst(prefix.count)))
            }
            return humanize(id)
        }
    }

    /// Returns `categories` with any missing top-level id from `requiredIds` added
    /// (taken from the static catalog, or as a leaf), so every currently selected
    /// value has a matching picker tag. Subcategories missing from a parent the API
    /// returned are filled in from the catalog the same way.
    static func ensuring(_ requiredIds: [String?], in categories: [AppCategoryModel]) -> [AppCategoryModel] {
        var result = categories
        for case let id? in requiredIds where !id.isEmpty {
            if result.contains(where: { $0.id == id }) { continue }
            // A subcategory id: make sure its parent carries it.
            if let parentIndex = result.firstIndex(where: { id.hasPrefix($0.id + "_") }) {
                if !result[parentIndex].subcategories.contains(where: { $0.id == id }) {
                    result[parentIndex].subcategories.append(AppCategoryModel(id: id))
                }
                continue
            }
            if let parent = all.first(where: { id.hasPrefix($0.id + "_") }) {
                var copy = parent
                if !copy.subcategories.contains(where: { $0.id == id }) {
                    copy.subcategories.append(AppCategoryModel(id: id))
                }
                result.append(copy)
                continue
            }
            result.append(all.first(where: { $0.id == id }) ?? AppCategoryModel(id: id))
        }
        return result
    }

    /// Fallback for ids this catalog does not know yet: `FOO_AND_BAR` → "Foo & Bar".
    static func humanize(_ id: String) -> String {
        id.split(separator: "_")
            .map { $0 == "AND" ? "&" : $0.capitalized }
            .joined(separator: " ")
    }
}
