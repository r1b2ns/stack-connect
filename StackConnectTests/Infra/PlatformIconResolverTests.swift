import XCTest
@testable import StackConnect

final class PlatformIconResolverTests: XCTestCase {

    // MARK: - Newest-per-platform

    func testGroupsByPlatformAndPicksNewestIcon() {
        let builds = [
            makeBuild(id: "b1", uploadedDate: date(100), iconUrl: "https://cdn/ios-old.png", platform: "IOS"),
            makeBuild(id: "b2", uploadedDate: date(300), iconUrl: "https://cdn/ios-new.png", platform: "IOS"),
            makeBuild(id: "b3", uploadedDate: date(200), iconUrl: "https://cdn/tv.png", platform: "TV_OS")
        ]

        let icons = PlatformIconResolver.icons(from: builds)

        XCTAssertEqual(icons.count, 2)
        XCTAssertEqual(icons[.ios], "https://cdn/ios-new.png")
        XCTAssertEqual(icons[.tvOs], "https://cdn/tv.png")
    }

    // MARK: - nil/empty-icon fallthrough

    func testSkipsNilOrEmptyIconAndFallsBackToNextNewest() {
        let builds = [
            // Newest iOS build has no usable icon → should fall through.
            makeBuild(id: "b1", uploadedDate: date(400), iconUrl: nil, platform: "IOS"),
            makeBuild(id: "b2", uploadedDate: date(300), iconUrl: "", platform: "IOS"),
            makeBuild(id: "b3", uploadedDate: date(200), iconUrl: "https://cdn/ios-fallback.png", platform: "IOS")
        ]

        let icons = PlatformIconResolver.icons(from: builds)

        XCTAssertEqual(icons[.ios], "https://cdn/ios-fallback.png")
    }

    // MARK: - Unmapped platform excluded

    func testExcludesUnmappedPlatformStrings() {
        let builds = [
            makeBuild(id: "b1", uploadedDate: date(100), iconUrl: "https://cdn/ios.png", platform: "IOS"),
            makeBuild(id: "b2", uploadedDate: date(100), iconUrl: "https://cdn/watch.png", platform: "WATCH_OS")
        ]

        let icons = PlatformIconResolver.icons(from: builds)

        XCTAssertEqual(icons.count, 1)
        XCTAssertEqual(icons[.ios], "https://cdn/ios.png")
    }

    /// Alias spellings the ASC API can return still map (e.g. `TVOS` → tvOS).
    func testMapsAliasPlatformSpellings() {
        let builds = [
            makeBuild(id: "b1", uploadedDate: date(100), iconUrl: "https://cdn/tv.png", platform: "TVOS"),
            makeBuild(id: "b2", uploadedDate: date(100), iconUrl: "https://cdn/mac.png", platform: "MACOS")
        ]

        let icons = PlatformIconResolver.icons(from: builds)

        XCTAssertEqual(icons[.tvOs], "https://cdn/tv.png")
        XCTAssertEqual(icons[.macOs], "https://cdn/mac.png")
    }

    // MARK: - nil-uploadedDate treated as oldest

    func testTreatsNilUploadedDateAsOldest() {
        let builds = [
            makeBuild(id: "b1", uploadedDate: nil, iconUrl: "https://cdn/ios-undated.png", platform: "IOS"),
            makeBuild(id: "b2", uploadedDate: date(50), iconUrl: "https://cdn/ios-dated.png", platform: "IOS")
        ]

        let icons = PlatformIconResolver.icons(from: builds)

        // The dated build outranks the undated one even though it appears later.
        XCTAssertEqual(icons[.ios], "https://cdn/ios-dated.png")
    }

    // MARK: - No icon-bearing build omits platform

    func testWithNoIconBearingBuildOmitsPlatform() {
        let builds = [
            makeBuild(id: "b1", uploadedDate: date(100), iconUrl: nil, platform: "IOS"),
            makeBuild(id: "b2", uploadedDate: date(200), iconUrl: "", platform: "IOS")
        ]

        let icons = PlatformIconResolver.icons(from: builds)

        XCTAssertNil(icons[.ios])
        XCTAssertTrue(icons.isEmpty)
    }

    // MARK: - Empty input

    func testEmptyInputReturnsEmptyMap() {
        XCTAssertTrue(PlatformIconResolver.icons(from: []).isEmpty)
    }

    // MARK: - Helpers

    private func makeBuild(
        id: String,
        uploadedDate: Date?,
        iconUrl: String?,
        platform: String?
    ) -> BuildModel {
        BuildModel(
            id: id,
            uploadedDate: uploadedDate,
            iconUrl: iconUrl,
            platform: platform
        )
    }

    /// `Date(timeIntervalSince1970:)` sugar so tests read as relative ages.
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
