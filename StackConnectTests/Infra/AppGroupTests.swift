import XCTest
import StackCore

/// `AppGroup.identifier` comes from the `AppGroupIdentifier` Info.plist key
/// (the `APP_GROUP_IDENTIFIER` build setting), with the maintainer's group as
/// the fallback. These tests don't assume a specific group: CI and contributors
/// build with their own one through `Configs/Local.xcconfig`.
final class AppGroupTests: XCTestCase {

    func testReadsTheIdentifierFromTheInfoDictionary() {
        let info: [String: Any] = [AppGroup.infoPlistKey: "group.com.example.stackconnect"]

        XCTAssertEqual(AppGroup.identifier(infoDictionary: info), "group.com.example.stackconnect")
    }

    func testTrimsWhitespaceAroundTheIdentifier() {
        let info: [String: Any] = [AppGroup.infoPlistKey: "  group.com.example.stackconnect\n"]

        XCTAssertEqual(AppGroup.identifier(infoDictionary: info), "group.com.example.stackconnect")
    }

    func testFallsBackWhenTheInfoDictionaryIsMissing() {
        XCTAssertEqual(AppGroup.identifier(infoDictionary: nil), AppGroup.defaultIdentifier)
    }

    func testFallsBackWhenTheKeyIsMissing() {
        XCTAssertEqual(AppGroup.identifier(infoDictionary: [:]), AppGroup.defaultIdentifier)
    }

    func testFallsBackWhenTheValueIsEmpty() {
        let info: [String: Any] = [AppGroup.infoPlistKey: "   "]

        XCTAssertEqual(AppGroup.identifier(infoDictionary: info), AppGroup.defaultIdentifier)
    }

    func testFallsBackWhenTheBuildSettingWasNotExpanded() {
        let info: [String: Any] = [AppGroup.infoPlistKey: "$(APP_GROUP_IDENTIFIER)"]

        XCTAssertEqual(AppGroup.identifier(infoDictionary: info), AppGroup.defaultIdentifier)
    }

    func testFallsBackWhenTheValueIsNotAString() {
        let info: [String: Any] = [AppGroup.infoPlistKey: 42]

        XCTAssertEqual(AppGroup.identifier(infoDictionary: info), AppGroup.defaultIdentifier)
    }

    func testDefaultIdentifierIsTheMaintainersGroup() {
        XCTAssertEqual(AppGroup.defaultIdentifier, "group.zeroSixteen.stackconnect")
    }

    /// The host app (Bundle.main for hosted unit tests) carries the expanded
    /// build setting, and the shared identifier is that value.
    func testHostAppBundleCarriesTheExpandedIdentifier() throws {
        let value = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: AppGroup.infoPlistKey) as? String,
            "AppGroupIdentifier missing from the host app's Info.plist (project.yml info properties)"
        )

        XCTAssertFalse(value.isEmpty)
        XCTAssertFalse(value.contains("$("), "APP_GROUP_IDENTIFIER was not expanded")
        XCTAssertTrue(value.hasPrefix("group."))
        XCTAssertEqual(AppGroup.identifier, value)
    }
}
