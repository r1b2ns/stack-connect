import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AnalyticsServiceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var provider: MockAnalyticsProvider!
    private var sut: AnalyticsService!

    override func setUp() async throws {
        suiteName = "AnalyticsServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        settings = AppSettings(defaults: defaults)
        provider = MockAnalyticsProvider()
        sut = AnalyticsService(providers: [provider], settings: settings, bundle: Bundle(for: Self.self))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        provider = nil
        settings = nil
        defaults = nil
    }

    // MARK: - Default

    func testDefaultsToEnabled() {
        XCTAssertTrue(sut.isEnabled)
        XCTAssertTrue(settings.isEnabled(.analyticsEnabled))
    }

    func testTrackReachesProvidersWhenEnabled() {
        sut.track(.screenView(.settings))

        XCTAssertEqual(provider.sentEventNames, ["screen_view"])
        XCTAssertEqual(provider.sentEvents.first?.parameters["screen_name"], .string("settings"))
    }

    func testTrackFansOutToEveryProvider() {
        let second = MockAnalyticsProvider()
        let service = AnalyticsService(providers: [provider, second], settings: settings)

        service.track(.buttonTap(.license, on: .settings))

        XCTAssertEqual(provider.sentEventNames, ["button_tap"])
        XCTAssertEqual(second.sentEventNames, ["button_tap"])
    }

    // MARK: - Opt-out

    func testDisablingSendsExactlyOneDisabledEventThenDropsTracking() {
        sut.setEnabled(false)
        sut.track(.screenView(.home))
        sut.track(.buttonTap(.accounts, on: .settings))

        XCTAssertEqual(provider.sentEventNames, ["analytics_disabled"])
        XCTAssertFalse(sut.isEnabled)
        XCTAssertFalse(settings.isEnabled(.analyticsEnabled))
    }

    func testDisabledEventIsSentBeforeTheSettingIsPersisted() {
        // A provider that captures the persisted value at the moment it receives the event.
        final class SpyProvider: AnalyticsProvider, @unchecked Sendable {
            let settings: AppSettings
            var enabledWhenSent: [String: Bool] = [:]
            init(settings: AppSettings) { self.settings = settings }
            func send(_ event: AnalyticsEvent) { enabledWhenSent[event.name] = settings.isEnabled(.analyticsEnabled) }
            func flush() async {}
            func reset() {}
        }
        let spy = SpyProvider(settings: settings)
        let service = AnalyticsService(providers: [spy], settings: settings)

        service.setEnabled(false)

        XCTAssertEqual(spy.enabledWhenSent["analytics_disabled"], true)
        XCTAssertFalse(settings.isEnabled(.analyticsEnabled))
    }

    func testDisablingTwiceSendsOneEventTotal() async {
        sut.setEnabled(false)
        await sut.pendingFlush?.value
        sut.setEnabled(false)
        await sut.pendingFlush?.value

        XCTAssertEqual(provider.sentEventNames, ["analytics_disabled"])
        XCTAssertEqual(provider.flushCount, 1)
        XCTAssertEqual(provider.resetCount, 1)
    }

    func testEnablingWhenAlreadyEnabledSendsNothing() {
        sut.setEnabled(true)

        XCTAssertTrue(provider.sentEvents.isEmpty)
        XCTAssertNil(sut.pendingFlush)
    }

    func testFlushAndResetAreCalledOnOptOut() async {
        sut.setEnabled(false)
        await sut.pendingFlush?.value

        XCTAssertEqual(provider.flushCount, 1)
        XCTAssertEqual(provider.resetCount, 1)
    }

    func testPersistedOptOutIsRespectedByAFreshInstance() {
        sut.setEnabled(false)

        let reopenedProvider = MockAnalyticsProvider()
        let reopened = AnalyticsService(providers: [reopenedProvider], settings: AppSettings(defaults: defaults))
        reopened.track(.screenView(.home))

        XCTAssertFalse(reopened.isEnabled)
        XCTAssertTrue(reopenedProvider.sentEvents.isEmpty)
    }

    // MARK: - Re-enable

    func testReEnablingSendsEnabledEventAndResumesTracking() {
        sut.setEnabled(false)
        sut.setEnabled(true)
        sut.track(.screenView(.home))

        XCTAssertEqual(provider.sentEventNames, ["analytics_disabled", "analytics_enabled", "screen_view"])
        XCTAssertTrue(sut.isEnabled)
        XCTAssertTrue(settings.isEnabled(.analyticsEnabled))
    }

    // MARK: - Vendor collection switch

    func testApplyCollectionSettingPushesEnabledAtLaunch() {
        sut.applyCollectionSetting()

        XCTAssertEqual(provider.calls, [.setCollectionEnabled(true)])
    }

    func testApplyCollectionSettingPushesPersistedOptOutAtLaunch() {
        settings.setEnabled(false, for: .analyticsEnabled)

        sut.applyCollectionSetting()

        XCTAssertEqual(provider.calls, [.setCollectionEnabled(false)])
    }

    func testApplyCollectionSettingSendsNoEvent() {
        sut.applyCollectionSetting()

        XCTAssertTrue(provider.sentEvents.isEmpty)
    }

    func testOptOutLogsDisabledEventBeforeDisablingCollection() async {
        sut.setEnabled(false)
        await sut.pendingFlush?.value

        XCTAssertEqual(provider.calls, [
            .send("analytics_disabled"),
            .flush,
            .setCollectionEnabled(false),
            .reset
        ])
    }

    func testOptInEnablesCollectionBeforeSendingEnabledEvent() async {
        sut.setEnabled(false)
        await sut.pendingFlush?.value

        sut.setEnabled(true)

        XCTAssertEqual(Array(provider.calls.suffix(2)), [
            .setCollectionEnabled(true),
            .send("analytics_enabled")
        ])
        XCTAssertEqual(provider.collectionEnabledCalls, [false, true])
    }

    func testRedundantSetEnabledDoesNotTouchCollection() {
        sut.setEnabled(true)

        XCTAssertTrue(provider.collectionEnabledCalls.isEmpty)
    }

    func testProviderWithoutCollectionSwitchUsesDefaultNoOp() {
        // Only implements the required methods: the protocol extension supplies
        // `setCollectionEnabled`, so existing providers keep compiling.
        struct MinimalProvider: AnalyticsProvider {
            func send(_ event: AnalyticsEvent) {}
            func flush() async {}
            func reset() {}
        }
        let service = AnalyticsService(providers: [MinimalProvider()], settings: settings)

        service.applyCollectionSetting()
        service.setEnabled(false)
        service.setEnabled(true)

        XCTAssertTrue(service.isEnabled)
    }

    // MARK: - Bootstrap

    func testBootstrapSkipsFirebaseWithoutConfigFile() {
        // The test bundle never contains GoogleService-Info.plist.
        XCTAssertFalse(AnalyticsBootstrap.shouldUseFirebase(bundle: Bundle(for: Self.self), processInfo: .processInfo))
    }

    func testBootstrapSkipsFirebaseWhileHostingTests() {
        // Even the app bundle (which may contain the plist locally) is skipped
        // when XCTest is driving the process.
        XCTAssertFalse(AnalyticsBootstrap.shouldUseFirebase(bundle: .main, processInfo: .processInfo))
    }

    func testBootstrapFallsBackToLogProviderOnly() {
        let providers = AnalyticsBootstrap.makeDefaultProviders(bundle: Bundle(for: Self.self))

        XCTAssertEqual(providers.count, 1)
        XCTAssertTrue(providers.first is LogAnalyticsProvider)
    }

    // MARK: - Standard parameters

    func testStandardParametersAreAttachedToEveryEvent() throws {
        sut.track(.screenView(.home))
        sut.setEnabled(false)

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let expectedOS = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        XCTAssertEqual(provider.sentEvents.count, 2)
        for event in provider.sentEvents {
            XCTAssertEqual(event.parameters["platform"], .string("ios"))
            XCTAssertEqual(event.parameters["os_version"], .string(expectedOS))
            XCTAssertNotNil(event.parameters["app_version"])
            XCTAssertNotNil(event.parameters["build_number"])
        }
    }

    func testStandardParametersComeFromTheInjectedBundle() throws {
        let bundle = Bundle(for: Self.self)
        let info = bundle.infoDictionary
        sut.track(.screenView(.home))

        let event = try XCTUnwrap(provider.sentEvents.first)
        XCTAssertEqual(event.parameters["app_version"], .string(info?["CFBundleShortVersionString"] as? String ?? "unknown"))
        XCTAssertEqual(event.parameters["build_number"], .string(info?["CFBundleVersion"] as? String ?? "unknown"))
    }

    func testNoUserIdentifierIsAttached() throws {
        sut.track(.screenView(.home))

        let keys = try XCTUnwrap(provider.sentEvents.first).parameters.keys
        XCTAssertEqual(Set(keys), ["screen_name", "app_version", "build_number", "platform", "os_version"])
    }

    // MARK: - Factories

    func testButtonTapFactory() {
        let event = AnalyticsEvent.buttonTap(.deleteAllAccounts, on: .settings)

        XCTAssertEqual(event.name, "button_tap")
        XCTAssertEqual(event.parameters, [
            "button_name": .string("delete_all_accounts"),
            "screen_name": .string("settings")
        ])
    }

    func testActionFactoryWithResultAndReservedKeysWin() {
        let event = AnalyticsEvent.action(
            .deleteAllAccounts,
            on: .settings,
            result: .success,
            parameters: ["count": .int(2), "screen_name": .string("spoofed")]
        )

        XCTAssertEqual(event.name, "action")
        XCTAssertEqual(event.parameters, [
            "action_name": .string("delete_all_accounts"),
            "screen_name": .string("settings"),
            "result": .string("success"),
            "count": .int(2)
        ])
    }

    func testActionFactoryWithoutResultOmitsIt() {
        let event = AnalyticsEvent.action(.syncApps, on: .appList)

        XCTAssertNil(event.parameters["result"])
    }

    func testScreenRawValuesAreUniqueSnakeCase() {
        let raws = AnalyticsScreen.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)
        for raw in raws {
            XCTAssertNotNil(raw.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression), raw)
        }
    }

    func testLogProviderFormatIsDeterministic() {
        let event = AnalyticsEvent(name: "button_tap", parameters: ["screen_name": .string("settings"), "button_name": .string("license")])

        XCTAssertEqual(LogAnalyticsProvider.format(event), "button_tap {button_name=license, screen_name=settings}")
    }
}
