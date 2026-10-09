import UIKit
import XCTest
@testable import StackConnect

/// Assertions check the dynamic parts (values, layout, omissions) rather than
/// full localized sentences, so they hold in any simulator language.
final class ErrorShareReportTests: XCTestCase {

    private let playMessage = """
        Google Play denied access to this service account.
        Google Play Android Developer API is not enabled for this service account's Google Cloud project. \
        Enable it at https://console.developers.google.com/apis/api/androidpublisher.googleapis.com/overview?project=123456789012, \
        wait a few minutes, then retry.
        """

    private let consoleURL = "https://console.developers.google.com/apis/api/androidpublisher.googleapis.com/overview?project=123456789012"

    /// 2026-10-09 17:32:05 UTC.
    private let fixedDate = Date(timeIntervalSince1970: 1_791_567_125)

    private func makeEnvironment(timeZone: TimeZone = TimeZone(secondsFromGMT: -3 * 3600)!) -> ErrorReportEnvironment {
        ErrorReportEnvironment(
            appVersion: "1.4.0",
            buildNumber: "42",
            osName: "iOS",
            osVersion: "26.1",
            deviceModel: "iPhone (iPhone18,2)",
            date: fixedDate,
            timeZone: timeZone
        )
    }

    private func makeFullContext() -> ErrorReportContext {
        ErrorReportContext(
            screen: "Ratings & Reviews",
            store: "Google Play",
            accountName: "Acme Play",
            appName: "Acme",
            appIdentifier: "com.acme.app"
        )
    }

    private func makeReport(message: String? = nil, context: ErrorReportContext? = nil) -> ErrorShareReport {
        ErrorShareReport.make(
            message: message ?? playMessage,
            context: context ?? makeFullContext(),
            environment: makeEnvironment()
        )
    }

    private func lines(of text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    // MARK: - All Fields

    func testReportContainsEveryContextAndEnvironmentValue() {
        let report = makeReport()

        XCTAssertTrue(report.text.contains("Ratings & Reviews"))
        XCTAssertTrue(report.text.contains("Google Play"))
        XCTAssertTrue(report.text.contains("Acme Play"))
        XCTAssertTrue(report.text.contains("Acme (com.acme.app)"), "App name with its identifier")
        XCTAssertTrue(report.text.contains("1.4.0 (42)"), "Version with its build")
        XCTAssertTrue(report.text.contains("iOS 26.1"))
        XCTAssertTrue(report.text.contains("iPhone (iPhone18,2)"))
        XCTAssertTrue(report.text.contains("StackConnect"), "Report title names the app")
    }

    func testDateIsISO8601WithTimeZoneOffset() {
        XCTAssertTrue(makeReport().text.contains("2026-10-09T14:32:05-03:00"))

        let utcReport = ErrorShareReport.make(
            message: playMessage,
            context: makeFullContext(),
            environment: makeEnvironment(timeZone: TimeZone(identifier: "UTC")!)
        )
        XCTAssertTrue(utcReport.text.contains("2026-10-09T17:32:05Z"))
    }

    func testSubjectNamesTheScreen() {
        let report = makeReport()

        XCTAssertTrue(report.subject.contains("Ratings & Reviews"))
        XCTAssertTrue(report.subject.contains("StackConnect"))
        XCTAssertFalse(report.subject.contains("\n"))
    }

    func testReportIsGroupedInFourBlocks() {
        // Title, context, error message, environment.
        let blocks = makeReport(message: "Boom").text.components(separatedBy: "\n\n")

        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(lines(of: blocks[1]).count, 4, "Screen, store, account, app")
        XCTAssertEqual(lines(of: blocks[2]).last, "Boom")
        XCTAssertEqual(lines(of: blocks[3]).count, 4, "Version, OS, device, date")
    }

    // MARK: - Message

    func testMessageIsPreservedVerbatimWithItsURL() {
        let report = makeReport()

        XCTAssertTrue(report.text.contains(playMessage))
        XCTAssertTrue(report.text.contains(consoleURL))
        // On its own lines, so nothing is glued to the link.
        XCTAssertTrue(report.text.contains("\n" + playMessage + "\n"))
    }

    func testMessageIsNotTrimmedOrRewritten() {
        let message = "  Line one\n\nLine two with a trailing space "
        let report = makeReport(message: message)

        XCTAssertTrue(report.text.contains(message))
    }

    // MARK: - Optional Fields

    func testMissingOptionalFieldsAreOmittedWithoutBlankLines() {
        let full = makeReport(message: "Boom")
        let minimal = makeReport(message: "Boom", context: ErrorReportContext(screen: "Apps"))

        XCTAssertEqual(lines(of: full.text).count - lines(of: minimal.text).count, 3, "Store, account and app lines are left out")
        XCTAssertEqual(minimal.text.components(separatedBy: "\n\n").count, 4)
        XCTAssertFalse(minimal.text.contains("\n\n\n"))
        XCTAssertFalse(lines(of: minimal.text).contains { $0.hasSuffix(": ") || $0.hasSuffix("：") }, "No label without a value")
        XCTAssertTrue(minimal.text.contains("Apps"))
    }

    func testBlankOptionalFieldsAreOmitted() {
        let blank = makeReport(
            message: "Boom",
            context: ErrorReportContext(screen: "Apps", store: "  ", accountName: "\n", appName: "", appIdentifier: " ")
        )
        let minimal = makeReport(message: "Boom", context: ErrorReportContext(screen: "Apps"))

        XCTAssertEqual(blank, minimal)
    }

    func testValuesAreTrimmed() {
        let padded = makeReport(
            message: "Boom",
            context: ErrorReportContext(screen: " Apps ", store: " Google Play ", accountName: " Acme Play\n", appName: "\tAcme ")
        )
        let trimmed = makeReport(
            message: "Boom",
            context: ErrorReportContext(screen: "Apps", store: "Google Play", accountName: "Acme Play", appName: "Acme")
        )

        XCTAssertEqual(padded, trimmed)
    }

    func testAppWithOnlyAnIdentifierShowsTheIdentifier() {
        let report = makeReport(context: ErrorReportContext(screen: "Tracks", appIdentifier: "com.acme.app"))

        XCTAssertTrue(report.text.contains("com.acme.app"))
        XCTAssertFalse(report.text.contains("(com.acme.app)"))
    }

    func testAppWithOnlyANameShowsTheName() {
        let report = makeReport(message: "Boom", context: ErrorReportContext(screen: "Tracks", appName: "Acme"))

        // The context block only: the environment block has "(…)" for the build.
        let contextBlock = report.text.components(separatedBy: "\n\n")[1]
        XCTAssertTrue(contextBlock.contains("Acme"))
        XCTAssertFalse(contextBlock.contains("("), "No identifier in parentheses")
    }

    func testAppNameEqualToIdentifierIsShownOnce() {
        // A Google Play app without a title is displayed by its package name.
        let report = makeReport(context: ErrorReportContext(screen: "Tracks", appName: "com.acme.app", appIdentifier: "com.acme.app"))

        XCTAssertEqual(report.text.components(separatedBy: "com.acme.app").count - 1, 1)
    }

    // MARK: - Context From Models

    func testContextFromAccountTakesOnlyItsNameAndStore() {
        let account = AccountModel(name: "Acme Play", providerType: .googlePlay)
        let context = ErrorReportContext(screen: "Ratings & Reviews", account: account, appName: "Acme", appIdentifier: "com.acme.app")

        XCTAssertEqual(context.screen, "Ratings & Reviews")
        XCTAssertEqual(context.store, ProviderType.googlePlay.displayName)
        XCTAssertEqual(context.accountName, "Acme Play")
        XCTAssertEqual(context.appName, "Acme")
        XCTAssertEqual(context.appIdentifier, "com.acme.app")
    }

    func testContextFromAppleAccountUsesAppStoreConnect() {
        let account = AccountModel(name: "Acme Team", providerType: .apple)
        let context = ErrorReportContext(screen: "Ratings & Reviews", account: account)

        XCTAssertEqual(context.store, ProviderType.apple.displayName)
        XCTAssertNil(context.appName)
        XCTAssertNil(context.appIdentifier)
    }

    func testContextFromGooglePlayAppUsesDisplayNameAndPackageName() {
        let account = AccountModel(name: "Acme Play", providerType: .googlePlay)
        let titled = GooglePlayAppItem(id: "1", packageName: "com.acme.app", title: "Acme", isManuallyAdded: false)
        let untitled = GooglePlayAppItem(id: "2", packageName: "com.acme.other", title: nil, isManuallyAdded: true)

        let titledContext = ErrorReportContext(screen: "Tracks", account: account, app: titled)
        XCTAssertEqual(titledContext.appName, "Acme")
        XCTAssertEqual(titledContext.appIdentifier, "com.acme.app")

        let untitledContext = ErrorReportContext(screen: "Tracks", account: account, app: untitled)
        XCTAssertEqual(untitledContext.appName, "com.acme.other")
        XCTAssertEqual(untitledContext.appIdentifier, "com.acme.other")
    }

    // MARK: - Secrets

    func testReportNeverContainsCredentials() {
        let keychain = MockKeyStorable()
        let account = AccountModel(name: "Acme Play", providerType: .googlePlay)
        let keyFile = GooglePlayTestFixtures.serviceAccountJSON()
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: keyFile), forKey: "credentials.\(account.id)")
        let app = GooglePlayAppItem(id: "1", packageName: "com.acme.app", title: "Acme", isManuallyAdded: false)

        let report = ErrorShareReport.make(
            message: "Google Play is temporarily unavailable.",
            context: ErrorReportContext(screen: "Tracks", account: account, app: app),
            environment: makeEnvironment()
        )

        for secret in [GooglePlayTestFixtures.privateKeyId, "PRIVATE KEY", "MIIEfake", GooglePlayTestFixtures.clientEmail, account.id] {
            XCTAssertFalse(report.text.contains(secret), "Report leaks \(secret)")
            XCTAssertFalse(report.subject.contains(secret), "Subject leaks \(secret)")
        }
    }

    // MARK: - Environment

    @MainActor
    func testCurrentEnvironmentReadsTheRunningApp() {
        let info = Bundle.main.infoDictionary
        let environment = ErrorReportEnvironment.current(date: fixedDate)

        XCTAssertEqual(environment.appVersion, info?["CFBundleShortVersionString"] as? String)
        XCTAssertEqual(environment.buildNumber, info?["CFBundleVersion"] as? String)
        XCTAssertEqual(environment.osName, UIDevice.current.systemName)
        XCTAssertEqual(environment.osVersion, UIDevice.current.systemVersion)
        XCTAssertTrue(environment.deviceModel.hasPrefix(UIDevice.current.model))
        XCTAssertEqual(environment.date, fixedDate)
        XCTAssertEqual(environment.timeZone, .current)
    }
}
