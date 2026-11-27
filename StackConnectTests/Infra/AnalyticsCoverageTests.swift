import XCTest
import StackProtocols
import UserNotifications
@testable import StackConnect

/// The analytics added for coverage gaps: shared dimensions and buckets,
/// `error_shown` de-duplication, search sessions, deep-link sources, the
/// notification permission flow, the offline banner and screen-less actions.
@MainActor
final class AnalyticsCoverageTests: XCTestCase {

    // MARK: - Buckets

    func testDurationBuckets() {
        XCTAssertEqual(AnalyticsDurationBucket(seconds: 0), .under5s)
        XCTAssertEqual(AnalyticsDurationBucket(seconds: 4.99), .under5s)
        XCTAssertEqual(AnalyticsDurationBucket(seconds: 5), .from5To15s)
        XCTAssertEqual(AnalyticsDurationBucket(seconds: 15), .from15To30s)
        XCTAssertEqual(AnalyticsDurationBucket(seconds: 30), .from30To60s)
        XCTAssertEqual(AnalyticsDurationBucket(seconds: 60), .over60s)
        XCTAssertEqual(AnalyticsDurationBucket(duration: .milliseconds(14_900)), .from5To15s)
    }

    func testCountBuckets() {
        XCTAssertEqual([0, 1, 2, 5, 6, 20, 21, 500].map { AnalyticsCountBucket(count: $0).rawValue },
                       ["0", "1", "2_5", "2_5", "6_20", "6_20", "21_plus", "21_plus"])
    }

    func testDimensionRawValuesAreStableSnakeCase() {
        let raws = AnalyticsErrorPresentation.allCases.map(\.rawValue)
            + AnalyticsDurationBucket.allCases.map(\.rawValue)
            + SyncTrigger.allCases.map(\.rawValue)
            + DeepLinkSource.allCases.map(\.rawValue)
            + AnalyticsDeepLinkDestination.allCases.map(\.rawValue)
            + AnalyticsTrackKind.allCases.map(\.rawValue)
            + AnalyticsReleaseWriteKind.allCases.map(\.rawValue)
            + AnalyticsNavigationOrigin.allCases.map(\.rawValue)
            + AnalyticsSidebarDestination.allCases.map(\.rawValue)
            + AnalyticsUILayout.allCases.map(\.rawValue)
            + AnalyticsReviewsFilter.allCases.map(\.rawValue)
        for raw in raws {
            XCTAssertNotNil(raw.range(of: "^[a-z0-9][a-z0-9_]*$", options: .regularExpression), raw)
        }
    }

    func testSplitViewDimensionsFitFirebaseLimits() {
        let raws = AnalyticsNavigationOrigin.allCases.map(\.rawValue)
            + AnalyticsSidebarDestination.allCases.map(\.rawValue)
            + AnalyticsUILayout.allCases.map(\.rawValue)
            + AnalyticsReviewsFilter.allCases.map(\.rawValue)
            + [AnalyticsScreen.releaseQueueInReview, .releaseQueueAwaitingRelease].map(\.rawValue)
            + [AnalyticsAction.navigate, .find].map(\.rawValue)
        for raw in raws {
            XCTAssertLessThanOrEqual(raw.count, FirebaseAnalyticsPayload.maxStringValueLength, raw)
        }
        // User property values are capped at 36 characters.
        for layout in AnalyticsUILayout.allCases {
            XCTAssertEqual(FirebaseAnalyticsPayload.userProperty(name: AnalyticsUserProperty.uiLayout.rawValue, value: layout.rawValue)?.value,
                           layout.rawValue)
        }
    }

    func testNavigateEventPayloadPassesUnchanged() throws {
        let event = AnalyticsEvent.navigate(to: .account(id: "acc", section: .certificates), from: .menuCommand)

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: event))

        XCTAssertEqual(payload.name, "action")
        XCTAssertEqual(payload.parameters["destination"] as? String, "account_certificates")
        XCTAssertEqual(payload.parameters["source"] as? String, "menu_command")
        XCTAssertEqual(payload.parameters["action_name"] as? String, "navigate")
    }

    // MARK: - Screen-less actions

    func testActionWithoutScreenOmitsScreenName() {
        let event = AnalyticsEvent.action(.offlineBannerShown, on: nil, parameters: ["screen_name": .string("spoofed")])

        XCTAssertEqual(event.parameters, ["action_name": .string("offline_banner_shown")])
    }

    func testOfflineBannerIsTrackedOnlyWhenShown() {
        let analytics = MockAnalyticsTracker()

        OfflineBannerModifier.trackBannerIfShown(isConnected: true, with: analytics)
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        OfflineBannerModifier.trackBannerIfShown(isConnected: false, with: analytics)
        XCTAssertEqual(analytics.actions(of: .offlineBannerShown).count, 1)
        XCTAssertNil(analytics.trackedEvents.first?.parameters["screen_name"])
    }

    // MARK: - error_shown

    func testErrorShownIsSentOncePerDistinctMessage() {
        let analytics = MockAnalyticsTracker()
        var deduplicator = ErrorShownDeduplicator()

        for message in ["Offline", "Offline", "Offline", "Server down", "Server down", "Offline"] {
            StackTrackErrorShownModifier.reportIfNeeded(
                message: message,
                presentation: .inline,
                category: .network,
                on: .googlePlayTracks,
                deduplicator: &deduplicator,
                with: analytics
            )
        }

        XCTAssertEqual(analytics.errorShownEvents.count, 3, "Re-renders of the same error don't count again")
    }

    func testErrorShownCarriesScreenPresentationAndCategoryButNeverTheMessage() {
        let event = AnalyticsEvent.errorShown(on: .googlePlayTracks, presentation: .fullScreen, category: .forbidden)

        XCTAssertEqual(event.name, "error_shown")
        XCTAssertEqual(event.parameters, [
            "screen_name": .string("google_play_tracks"),
            "presentation": .string("full_screen"),
            "error_category": .string("forbidden")
        ])
    }

    func testErrorShownWithoutScreenOrCategoryOmitsThem() {
        let event = AnalyticsEvent.errorShown(on: nil, presentation: .inline, category: nil)

        XCTAssertEqual(event.parameters, ["presentation": .string("inline")])
    }

    func testShareErrorTapNeedsATrackedScreen() {
        let analytics = MockAnalyticsTracker()

        StackTrackShareErrorTapModifier.trackTap(on: nil, with: analytics)
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        StackTrackShareErrorTapModifier.trackTap(on: .appList, with: analytics)
        XCTAssertEqual(analytics.taps(of: .shareError).first?.parameters["screen_name"], .string("app_list"))
    }

    func testErrorCategoryParametersForAnyError() {
        XCTAssertEqual(AnalyticsErrorCategory.parameters(for: nil), [:])
        XCTAssertEqual(AnalyticsErrorCategory.parameters(for: URLError(.notConnectedToInternet)), ["error_category": .string("network")])
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: GooglePlayReleaseWriteError.denied("No")), .forbidden)
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: GooglePlayReleaseWriteError.missingCredentials), .invalidCredentials)
    }

    // MARK: - Search

    func testSearchIsReportedOncePerSessionWithABucketedCount() {
        let session = SearchAnalyticsSession()

        session.queryChanged("sec")
        session.resultCountChanged(7)
        let first = session.commit(on: .appList)
        session.queryChanged("secret app")
        session.resultCountChanged(1)
        let again = session.commit(on: .appList)

        XCTAssertEqual(first?.parameters, [
            "action_name": .string("search"),
            "screen_name": .string("app_list"),
            "result_count_bucket": .string("6_20")
        ], "Never the query")
        XCTAssertNil(again, "Refining the same search is the same session")
    }

    func testClearingTheQueryStartsANewSession() {
        let session = SearchAnalyticsSession()

        session.queryChanged("a")
        XCTAssertNotNil(session.commit(on: .devicesList))
        session.queryChanged("")
        XCTAssertNil(session.commit(on: .devicesList), "No search while the field is empty")
        session.queryChanged("b")
        session.resultCountChanged(0)

        XCTAssertEqual(session.commit(on: .devicesList)?.parameters["result_count_bucket"], .string("0"))
    }

    func testWhitespaceOnlyQueryIsNotASearch() {
        let session = SearchAnalyticsSession()

        session.queryChanged("   ")

        XCTAssertNil(session.commit(on: .userAccess))
    }

    // MARK: - Deep links

    func testDeepLinkSourceOfAnOpenedURL() throws {
        let widget = try XCTUnwrap(URL(string: "stackconnect://reviews?source=widget"))
        let plain = try XCTUnwrap(URL(string: "stackconnect://reviews"))

        XCTAssertEqual(DeepLinkSource(openedURL: widget), .widget)
        XCTAssertEqual(DeepLinkSource(openedURL: plain), .url)
        XCTAssertEqual(DeepLink(url: widget), .reviews, "The marker doesn't change the route")
    }

    func testWidgetRowLinksAreMarkedAndKeepTheirRoute() {
        let link = DeepLink.app(accountId: "acc", appId: "123").url

        let marked = WidgetLinkSource.marked(link)

        XCTAssertEqual(DeepLinkSource(openedURL: marked), .widget)
        XCTAssertEqual(DeepLink(url: marked), .app(accountId: "acc", appId: "123"))
        XCTAssertEqual(WidgetLinkSource.marked(marked), marked, "Marking twice adds nothing")
    }

    func testDeepLinkDestinationIsTheRouteKindOnly() throws {
        XCTAssertEqual(AnalyticsDeepLinkDestination(url: DeepLink.home.url), .home)
        XCTAssertEqual(AnalyticsDeepLinkDestination(url: DeepLink.reviews.url), .reviews)
        XCTAssertEqual(AnalyticsDeepLinkDestination(url: DeepLink.networkAudit.url), .networkAudit)
        XCTAssertEqual(AnalyticsDeepLinkDestination.networkAudit.rawValue, "network_audit")
        XCTAssertEqual(AnalyticsDeepLinkDestination(url: DeepLink.app(accountId: "a", appId: "b").url), .app)
        XCTAssertEqual(AnalyticsDeepLinkDestination(url: DeepLink.review(accountId: "a", appId: "b", reviewId: "c").url), .review)
        XCTAssertEqual(AnalyticsDeepLinkDestination(url: DeepLink.reimport(accountId: "a").url), .reimport)
        XCTAssertEqual(AnalyticsDeepLinkDestination(url: try XCTUnwrap(URL(string: "https://example.com"))), .unknown)
    }

    func testRouterTracksExternalOpensOnly() {
        let analytics = MockAnalyticsTracker()
        let router = DeepLinkRouter(analytics: analytics)
        let link = DeepLink.review(accountId: "secret-account", appId: "42", reviewId: "r1").url

        router.open(link, source: .notification)
        router.open(DeepLink.reimport(accountId: "acc").url)

        XCTAssertEqual(analytics.trackedEvents, [
            AnalyticsEvent(name: "app_opened_from", parameters: [
                "source": .string("notification"),
                "destination": .string("review")
            ])
        ], "In-app links are not tracked; ids never are")
        XCTAssertEqual(router.pending, DeepLink.reimport(accountId: "acc").url, "Routing is unchanged")
    }

    /// An App Store In-App Event open is a plain URL open.
    func testRouterTracksANetworkAuditOpenFromAURL() throws {
        let analytics = MockAnalyticsTracker()
        let router = DeepLinkRouter(analytics: analytics)
        let url = try XCTUnwrap(URL(string: "stackconnect://network-audit"))

        router.open(url, source: DeepLinkSource(openedURL: url))

        XCTAssertEqual(analytics.trackedEvents, [
            AnalyticsEvent(name: "app_opened_from", parameters: [
                "source": .string("url"),
                "destination": .string("network_audit")
            ])
        ])
        XCTAssertEqual(router.pending, url)
    }

    // MARK: - Notification permission

    func testGrantedPromptIsTrackedAndSetsTheUserProperty() async {
        let center = MockNotificationAuthorizationCenter(status: .notDetermined, grant: .success(true))
        let analytics = MockAnalyticsTracker()
        let sut = NotificationPermissionService(center: center, analytics: analytics, userProperties: analytics)

        let allowed = await sut.requestAuthorization(options: [.alert])

        XCTAssertTrue(allowed)
        XCTAssertEqual(center.requestCount, 1)
        XCTAssertEqual(analytics.results(of: .requestNotificationPermission), [.success])
        XCTAssertNil(analytics.trackedEvents.first?.parameters["screen_name"])
        XCTAssertEqual(analytics.userPropertyUpdates, [[.notificationsEnabled: "true"]])
    }

    func testDeniedPromptIsTrackedAsCancelled() async {
        let center = MockNotificationAuthorizationCenter(status: .notDetermined, grant: .success(false))
        let analytics = MockAnalyticsTracker()
        let sut = NotificationPermissionService(center: center, analytics: analytics, userProperties: analytics)

        await sut.requestAuthorization(options: [.alert])

        XCTAssertEqual(analytics.results(of: .requestNotificationPermission), [.cancelled])
        XCTAssertEqual(analytics.userPropertyUpdates, [[.notificationsEnabled: "false"]])
    }

    func testFailedPromptIsTrackedAsFailure() async {
        let center = MockNotificationAuthorizationCenter(status: .notDetermined, grant: .failure(URLError(.unknown)))
        let analytics = MockAnalyticsTracker()
        let sut = NotificationPermissionService(center: center, analytics: analytics, userProperties: analytics)

        let allowed = await sut.requestAuthorization(options: [.alert])

        XCTAssertFalse(allowed)
        XCTAssertEqual(analytics.results(of: .requestNotificationPermission), [.failure])
    }

    func testAnsweredPromptIsNotShownAgainButRefreshesTheProperty() async {
        let center = MockNotificationAuthorizationCenter(status: .provisional, grant: .success(true))
        let analytics = MockAnalyticsTracker()
        let sut = NotificationPermissionService(center: center, analytics: analytics, userProperties: analytics)

        let allowed = await sut.requestAuthorization(options: [.alert])
        center.status = .denied
        await sut.refreshUserProperty()

        XCTAssertTrue(allowed)
        XCTAssertEqual(center.requestCount, 0)
        XCTAssertTrue(analytics.trackedEvents.isEmpty, "No prompt, no event")
        XCTAssertEqual(analytics.userPropertyUpdates, [[.notificationsEnabled: "true"], [.notificationsEnabled: "false"]])
    }
}

// MARK: - Crashlytics

/// Crashlytics follows the analytics opt-out through `AnalyticsService`: its
/// collection switch and non-fatals go through the same gate as events.
@MainActor
final class CrashlyticsGatingTests: XCTestCase {

    private var defaults: UserDefaults!
    private var settings: AppSettings!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "CrashlyticsGatingTests.\(UUID().uuidString)")
        settings = AppSettings(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults = nil
        settings = nil
        try await super.tearDown()
    }

    private func makeService(client: MockCrashlyticsClient) -> AnalyticsService {
        AnalyticsService(providers: [CrashlyticsProvider(client: client)], settings: settings)
    }

    func testLaunchAppliesTheOptOutToCrashlytics() {
        let client = MockCrashlyticsClient()
        settings.setEnabled(false, for: .analyticsEnabled)

        makeService(client: client).applyCollectionSetting()

        XCTAssertEqual(client.collectionCalls, [false])
    }

    func testOptOutAndOptInSwitchCrashlyticsCollection() async {
        let client = MockCrashlyticsClient()
        let service = makeService(client: client)

        service.setEnabled(false)
        await service.pendingFlush?.value
        service.setEnabled(true)

        XCTAssertEqual(client.collectionCalls, [false, true])
    }

    func testNonFatalsAreGatedAndScrubbed() {
        let client = MockCrashlyticsClient()
        let service = makeService(client: client)
        let error = NSError(domain: "StackConnect.Server", code: 503, userInfo: [
            NSLocalizedDescriptionKey: "Account Secret Team failed",
            NSURLErrorFailingURLStringErrorKey: "https://example.com/apps/com.secret.app"
        ])

        service.recordNonFatal(error, category: .validation)
        XCTAssertTrue(client.recorded.isEmpty, "Expected user-side categories are never recorded")

        service.recordNonFatal(error, category: .server)
        let recorded = client.recorded.first
        XCTAssertEqual(recorded?.domain, "StackConnect.Server")
        XCTAssertEqual(recorded?.code, 503)
        XCTAssertEqual(recorded?.userInfo as? [String: String], ["error_category": "server"], "userInfo is replaced, never forwarded")

        service.setEnabled(false)
        service.recordNonFatal(error, category: .unknown)
        XCTAssertEqual(client.recorded.count, 1, "Nothing is recorded for an opted-out user")
    }

    func testCrashlyticsProviderSendsNoEvents() {
        let client = MockCrashlyticsClient()
        let service = makeService(client: client)

        service.track(.screenView(.home))

        XCTAssertTrue(client.recorded.isEmpty)
        XCTAssertTrue(client.collectionCalls.isEmpty)
    }

    func testFirebaseShipsAnalyticsAndCrashlyticsTogether() {
        let providers = AnalyticsBootstrap.firebaseProviders()

        XCTAssertTrue(providers.contains { $0 is FirebaseAnalyticsProvider })
        XCTAssertTrue(providers.contains { $0 is CrashlyticsProvider })
    }

    func testFirebaseIsNeverUsedInUnitTestHosts() {
        let processInfo = ProcessInfo.processInfo

        XCTAssertFalse(AnalyticsBootstrap.shouldUseFirebase(bundle: .main, processInfo: processInfo),
                       "Neither Analytics nor Crashlytics is set up while hosting tests")
    }
}

// MARK: - Mocks

/// `@unchecked Sendable`: state is guarded by `lock`.
private final class MockCrashlyticsClient: CrashlyticsClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _collectionCalls: [Bool] = []
    private var _recorded: [NSError] = []

    var collectionCalls: [Bool] { lock.withLock { _collectionCalls } }
    var recorded: [NSError] { lock.withLock { _recorded } }

    func setCollectionEnabled(_ enabled: Bool) {
        lock.withLock { _collectionCalls.append(enabled) }
    }

    func record(_ error: NSError) {
        lock.withLock { _recorded.append(error) }
    }
}

/// `@unchecked Sendable`: state is guarded by `lock`.
private final class MockNotificationAuthorizationCenter: NotificationAuthorizationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: UNAuthorizationStatus
    private var _requestCount = 0
    private let grant: Result<Bool, Error>

    var status: UNAuthorizationStatus {
        get { lock.withLock { _status } }
        set { lock.withLock { _status = newValue } }
    }
    var requestCount: Int { lock.withLock { _requestCount } }

    init(status: UNAuthorizationStatus, grant: Result<Bool, Error>) {
        self._status = status
        self.grant = grant
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        lock.withLock { _requestCount += 1 }
        let granted = try grant.get()
        status = granted ? .authorized : .denied
        return granted
    }
}
