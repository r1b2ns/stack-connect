import XCTest
@testable import StackConnect

final class FakeDataModeTests: XCTestCase {

    func testDisabledWithoutSwitches() {
        let mode = FakeDataMode(arguments: ["StackConnect"], environment: [:])
        XCTAssertFalse(mode.isEnabled)
        XCTAssertFalse(mode.shouldReset)
    }

    func testLaunchArgumentEnables() {
        let mode = FakeDataMode(arguments: ["StackConnect", "-StackFakeData", "YES"], environment: [:])
        XCTAssertTrue(mode.isEnabled)
        XCTAssertFalse(mode.shouldReset)
    }

    func testLaunchArgumentAcceptsTrueAndOne() {
        XCTAssertTrue(FakeDataMode(arguments: ["-StackFakeData", "true"], environment: [:]).isEnabled)
        XCTAssertTrue(FakeDataMode(arguments: ["-StackFakeData", "1"], environment: [:]).isEnabled)
    }

    func testEnvironmentEnables() {
        let mode = FakeDataMode(arguments: [], environment: ["STACK_FAKE_DATA": "1"])
        XCTAssertTrue(mode.isEnabled)
    }

    func testArgumentNoWinsOverEnvironment() {
        let mode = FakeDataMode(arguments: ["-StackFakeData", "NO"], environment: ["STACK_FAKE_DATA": "1"])
        XCTAssertFalse(mode.isEnabled)
    }

    func testLastArgumentOccurrenceWins() {
        let mode = FakeDataMode(arguments: ["-StackFakeData", "YES", "-StackFakeData", "NO"], environment: [:])
        XCTAssertFalse(mode.isEnabled)
    }

    func testArgumentWithoutValueIsIgnored() {
        XCTAssertFalse(FakeDataMode(arguments: ["-StackFakeData"], environment: [:]).isEnabled)
    }

    func testResetNeedsTheModeToBeEnabled() {
        let resetOnly = FakeDataMode(arguments: ["-StackFakeDataReset", "YES"], environment: [:])
        XCTAssertFalse(resetOnly.isEnabled)
        XCTAssertFalse(resetOnly.shouldReset)

        let both = FakeDataMode(arguments: ["-StackFakeData", "YES", "-StackFakeDataReset", "YES"], environment: [:])
        XCTAssertTrue(both.shouldReset)

        let viaEnvironment = FakeDataMode(arguments: [], environment: ["STACK_FAKE_DATA": "1", "STACK_FAKE_DATA_RESET": "YES"])
        XCTAssertTrue(viaEnvironment.shouldReset)
    }

    func testUnitTestHostIsNotInFakeMode() {
        // The test host is launched without the switches: real seams stay installed.
        XCTAssertFalse(FakeDataMode.current.isEnabled)
        XCTAssertTrue(KeychainStorable.shared is KeychainStorable)
        XCTAssertTrue(BackendEnvironment.coreProviders is RustCoreProviderFactory)
        XCTAssertTrue(BackendEnvironment.firebaseProviders is LiveFirebaseProviderFactory)
    }
}
