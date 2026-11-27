import XCTest
@testable import StackConnect

final class AnalyticsBootstrapTests: XCTestCase {

    private func mode(
        hasConfigFile: Bool = true,
        isUnitTestHost: Bool = false,
        isFakeData: Bool = false,
        isDebug: Bool,
        sendToFirebaseRequested: Bool = false
    ) -> AnalyticsFirebaseMode {
        AnalyticsBootstrap.firebaseMode(
            hasConfigFile: hasConfigFile,
            isUnitTestHost: isUnitTestHost,
            isFakeData: isFakeData,
            isDebug: isDebug,
            sendToFirebaseRequested: sendToFirebaseRequested
        )
    }

    // MARK: - Decision

    func testReleaseWithConfigFileSendsToFirebase() {
        XCTAssertEqual(mode(isDebug: false), .configuredWithCollection)
    }

    func testDebugConfiguresFirebaseButNeverCollectsByDefault() {
        XCTAssertEqual(mode(isDebug: true), .configuredWithoutCollection,
                       "Remote Config still needs a configured Firebase app")
    }

    func testDebugOptInSendsToFirebase() {
        XCTAssertEqual(mode(isDebug: true, sendToFirebaseRequested: true), .configuredWithCollection)
    }

    func testOptInIsIgnoredInRelease() {
        XCTAssertEqual(mode(isDebug: false, sendToFirebaseRequested: true), .configuredWithCollection)
        XCTAssertEqual(mode(isDebug: false, sendToFirebaseRequested: false), .configuredWithCollection)
    }

    func testNoConfigFileNeverConfiguresFirebase() {
        for isDebug in [true, false] {
            for optIn in [true, false] {
                XCTAssertEqual(mode(hasConfigFile: false, isDebug: isDebug, sendToFirebaseRequested: optIn), .notConfigured)
            }
        }
    }

    func testUnitTestHostNeverConfiguresFirebaseEvenWithOptIn() {
        XCTAssertEqual(mode(isUnitTestHost: true, isDebug: true, sendToFirebaseRequested: true), .notConfigured)
        XCTAssertEqual(mode(isUnitTestHost: true, isDebug: false), .notConfigured)
    }

    func testFakeDataNeverConfiguresFirebaseEvenWithOptIn() {
        XCTAssertEqual(mode(isFakeData: true, isDebug: true), .notConfigured)
        XCTAssertEqual(mode(isFakeData: true, isDebug: true, sendToFirebaseRequested: true), .notConfigured)
    }

    func testBundleBasedDecisionInThisTestHostIsNotConfigured() {
        XCTAssertEqual(
            AnalyticsBootstrap.firebaseMode(bundle: .main, processInfo: .processInfo, isDebug: true),
            .notConfigured
        )
    }

    // MARK: - Opt-in parsing

    func testLaunchArgumentName() {
        XCTAssertEqual(AnalyticsBootstrap.sendToFirebaseArgumentKey, "StackAnalyticsSendToFirebase")
        XCTAssertEqual(AnalyticsBootstrap.sendToFirebaseEnvironmentKey, "STACK_ANALYTICS_SEND_TO_FIREBASE")
    }

    func testOptInIsOffWithoutArgumentOrEnvironment() {
        XCTAssertFalse(AnalyticsBootstrap.isSendToFirebaseRequested(arguments: ["app"], environment: [:]))
    }

    func testOptInFromLaunchArgument() {
        for value in ["YES", "yes", "true", "1"] {
            XCTAssertTrue(AnalyticsBootstrap.isSendToFirebaseRequested(
                arguments: ["app", "-StackAnalyticsSendToFirebase", value], environment: [:]), value)
        }
        XCTAssertFalse(AnalyticsBootstrap.isSendToFirebaseRequested(
            arguments: ["app", "-StackAnalyticsSendToFirebase", "NO"], environment: [:]))
    }

    func testOptInArgumentWithoutValueIsOff() {
        XCTAssertFalse(AnalyticsBootstrap.isSendToFirebaseRequested(
            arguments: ["app", "-StackAnalyticsSendToFirebase"], environment: [:]))
    }

    func testOptInFromEnvironment() {
        XCTAssertTrue(AnalyticsBootstrap.isSendToFirebaseRequested(
            arguments: ["app"], environment: ["STACK_ANALYTICS_SEND_TO_FIREBASE": "1"]))
        XCTAssertFalse(AnalyticsBootstrap.isSendToFirebaseRequested(
            arguments: ["app"], environment: ["STACK_ANALYTICS_SEND_TO_FIREBASE": "0"]))
    }

    func testArgumentWinsOverEnvironment() {
        XCTAssertFalse(AnalyticsBootstrap.isSendToFirebaseRequested(
            arguments: ["app", "-StackAnalyticsSendToFirebase", "NO"],
            environment: ["STACK_ANALYTICS_SEND_TO_FIREBASE": "1"]))
        XCTAssertTrue(AnalyticsBootstrap.isSendToFirebaseRequested(
            arguments: ["app", "-StackAnalyticsSendToFirebase", "YES"],
            environment: ["STACK_ANALYTICS_SEND_TO_FIREBASE": "0"]))
    }

    func testLastArgumentOccurrenceWins() {
        XCTAssertTrue(AnalyticsBootstrap.isSendToFirebaseRequested(
            arguments: ["-StackAnalyticsSendToFirebase", "NO", "-StackAnalyticsSendToFirebase", "YES"],
            environment: [:]))
    }
}
