import XCTest
@testable import StackConnect

final class BuildPickerSheetTests: XCTestCase {

    private func build(id: String, platform: String) -> BuildModel {
        BuildModel(id: id, version: id, platform: platform)
    }

    func testNilPlatformReturnsAllBuilds() {
        let builds = [build(id: "1", platform: "IOS"), build(id: "2", platform: "TV_OS")]
        XCTAssertEqual(BuildPickerSheet.builds(builds, matching: nil).map(\.id), ["1", "2"])
    }

    func testPlatformFilterKeepsOnlyMatchingPlatform() {
        let builds = [
            build(id: "1", platform: "IOS"),
            build(id: "2", platform: "TV_OS"),
            build(id: "3", platform: "IOS")
        ]
        XCTAssertEqual(BuildPickerSheet.builds(builds, matching: .ios).map(\.id), ["1", "3"])
        XCTAssertEqual(BuildPickerSheet.builds(builds, matching: .tvOs).map(\.id), ["2"])
    }

    func testPlatformFilterWithNoMatchesReturnsEmpty() {
        let builds = [build(id: "1", platform: "IOS")]
        XCTAssertTrue(BuildPickerSheet.builds(builds, matching: .macOs).isEmpty)
    }
}
