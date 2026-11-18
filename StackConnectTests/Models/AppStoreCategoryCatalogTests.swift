import XCTest
@testable import StackConnect

/// App Store category names and the picker's tag guarantees. Expected names are
/// resolved through the string catalog (`L("Food & Drink")`) so the suite passes
/// in any simulator language; the English source keys are what QA asked for.
final class AppStoreCategoryCatalogTests: XCTestCase {

    private func L(_ key: String.LocalizationValue) -> String { String(localized: key) }

    func testAmpersandCategoriesUseAppStoreNames() {
        XCTAssertEqual(AppStoreCategoryCatalog.displayName(forCategoryId: "FOOD_AND_DRINK"), L("Food & Drink"))
        XCTAssertEqual(AppStoreCategoryCatalog.displayName(forCategoryId: "HEALTH_AND_FITNESS"), L("Health & Fitness"))
        XCTAssertEqual(AppStoreCategoryCatalog.displayName(forCategoryId: "PHOTO_AND_VIDEO"), L("Photo & Video"))
        XCTAssertEqual(AppStoreCategoryCatalog.displayName(forCategoryId: "GRAPHICS_AND_DESIGN"), L("Graphics & Design"))
        XCTAssertEqual(AppStoreCategoryCatalog.displayName(forCategoryId: "MAGAZINES_AND_NEWSPAPERS"), L("Magazines & Newspapers"))
    }

    func testEveryCatalogEntryHasAnExplicitName() {
        for category in AppStoreCategoryCatalog.all {
            let name = AppStoreCategoryCatalog.displayName(forCategoryId: category.id)
            XCTAssertFalse(name.isEmpty, "\(category.id) has an empty name")
            XCTAssertFalse(name.contains(" And "), "\(category.id) uses the mechanical joiner: \(name)")
            XCTAssertFalse(name.contains("_"), "\(category.id) → \(name)")
            for sub in category.subcategories {
                let subName = AppStoreCategoryCatalog.displayName(forSubcategoryId: sub.id, parentId: category.id)
                XCTAssertFalse(subName.uppercased().hasPrefix(category.id), "\(sub.id) must not repeat the parent: \(subName)")
                XCTAssertFalse(subName.contains("_"), "\(sub.id) → \(subName)")
            }
        }
    }

    func testCatalogContainsNavigationTravelAndAllTopLevelIds() {
        let ids = Set(AppStoreCategoryCatalog.all.map(\.id))
        XCTAssertEqual(ids.count, 26)
        XCTAssertTrue(ids.isSuperset(of: ["NAVIGATION", "TRAVEL", "WEATHER", "GAMES", "STICKERS", "MEDICAL", "SHOPPING"]))
    }

    func testSubcategoryNamesStripParentPrefix() {
        XCTAssertEqual(AppStoreCategoryCatalog.displayName(forSubcategoryId: "GAMES_ROLE_PLAYING", parentId: "GAMES"), L("Role Playing"))
        XCTAssertEqual(AppStoreCategoryCatalog.displayName(forSubcategoryId: "STICKERS_MOVIES_AND_TV", parentId: "STICKERS"), L("Movies & TV"))
        XCTAssertEqual(AppStoreCategoryCatalog.displayName(forSubcategoryId: "GAMES_NEW_GENRE", parentId: "GAMES"), "New Genre")
    }

    func testUnknownIdsFallBackToHumanizedAmpersand() {
        XCTAssertEqual(AppStoreCategoryCatalog.displayName(forCategoryId: "KIDS_AND_LEARNING"), "Kids & Learning")
    }

    func testModelDisplayNamesUseTheCatalog() {
        XCTAssertEqual(AppCategoryModel(id: "FOOD_AND_DRINK").displayName, L("Food & Drink"))
        XCTAssertEqual(AppCategoryModel(id: "GAMES_ACTION").subcategoryDisplayName(parentId: "GAMES"), L("Action"))
        XCTAssertEqual(AppleAccountConnection.formatCategoryId("PHOTO_AND_VIDEO"), L("Photo & Video"))
    }

    func testEnsuringAddsMissingSelectionsAsTags() {
        let fetched = [AppCategoryModel(id: "BOOKS"), AppCategoryModel(id: "GAMES", subcategories: [AppCategoryModel(id: "GAMES_ACTION")])]
        let result = AppStoreCategoryCatalog.ensuring(["NAVIGATION", "GAMES_PUZZLE", "TRAVEL", nil, "BOOKS"], in: fetched)

        let ids = result.map(\.id)
        XCTAssertEqual(ids, ["BOOKS", "GAMES", "NAVIGATION", "TRAVEL"], "Existing order is kept; missing ids are appended once.")
        XCTAssertEqual(result.first { $0.id == "GAMES" }?.subcategories.map(\.id), ["GAMES_ACTION", "GAMES_PUZZLE"])
    }

    func testEnsuringAddsParentForOrphanSubcategory() {
        let result = AppStoreCategoryCatalog.ensuring(["STICKERS_ART"], in: [AppCategoryModel(id: "BOOKS")])
        let stickers = result.first { $0.id == "STICKERS" }
        XCTAssertNotNil(stickers)
        XCTAssertTrue(stickers?.subcategories.contains { $0.id == "STICKERS_ART" } ?? false)
    }
}
