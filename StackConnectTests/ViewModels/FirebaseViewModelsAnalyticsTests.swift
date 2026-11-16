import XCTest
import StackProtocols
@testable import StackConnect

/// Analytics events of the Firebase screens (projects, project detail, apps,
/// Remote Config, Messaging) and Google Play apps. Only enums, booleans and
/// counts may appear as parameters — never IDs, names, bundle IDs, parameter
/// keys/values or campaign content.
@MainActor
final class FirebaseViewModelsAnalyticsTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        analytics = nil
        try await super.tearDown()
    }

    private var firebaseAccount: AccountModel { AccountModel(name: "Firebase", providerType: .firebase) }
    private var project: FirebaseProjectModel { FirebaseProjectModel(id: "p", displayName: "Project", projectId: "my-project") }

    private let iosApp = FirebaseAppModel(
        id: "1:123:ios:abc",
        displayName: "Secret App",
        appId: "1:123:ios:abc",
        platform: .ios,
        bundleId: "com.example.secret"
    )

    // MARK: - Project list

    func testProjectListLoadTracksNothingAndRefreshTracksFailure() async {
        let sut = FirebaseProjectListViewModel(account: firebaseAccount, keychain: MockKeyStorable(), analytics: analytics)

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .firebaseProjectList, result: .failure)])
    }

    // MARK: - Project detail

    func testReorderServicesTracksSuccessOffline() async {
        let sut = FirebaseProjectDetailViewModel(
            project: project,
            account: firebaseAccount,
            storage: MockPersistentStorable(),
            analytics: analytics
        )

        await sut.moveItem(from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(analytics.actions(of: .reorderServices), [.action(.reorderServices, on: .firebaseProjectDetail, result: .success)])
    }

    func testReorderServicesTracksFailureWhenStorageFails() async {
        let storage = MockPersistentStorable()
        await storage.failSave(FirebaseProjectMenuOrder.self)
        let sut = FirebaseProjectDetailViewModel(project: project, account: firebaseAccount, storage: storage, analytics: analytics)

        await sut.moveItem(from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(analytics.results(of: .reorderServices), [.failure])
    }

    // MARK: - App list

    private func makeAppListSUT() -> FirebaseAppListViewModel {
        FirebaseAppListViewModel(account: firebaseAccount, project: project, keychain: MockKeyStorable(), analytics: analytics)
    }

    func testAppListRefreshTracksFailureWithoutCredentials() async {
        let sut = makeAppListSUT()

        await sut.load()
        await sut.refresh()

        XCTAssertEqual(analytics.trackedEvents, [.action(.refresh, on: .firebaseAppList, result: .failure)])
    }

    func testAppWorkTracksTapsAndFailuresWithPlatformOnly() async {
        let sut = makeAppListSUT()
        let platform = [AnalyticsParameterKey.kind: AnalyticsValue.string("ios")]

        await sut.createApp(platform: .ios, identifier: "com.example.secret", nickname: "Secret", appStoreId: "123")
        await sut.updateNickname(iosApp, newName: "Renamed")
        await sut.removeApp(iosApp)

        XCTAssertEqual(analytics.taps(of: .create), [.buttonTap(.create, on: .createFirebaseApp)])
        XCTAssertEqual(analytics.taps(of: .save), [.buttonTap(.save, on: .firebaseAppDetail)])
        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .firebaseAppList)])
        XCTAssertEqual(analytics.actions(of: .createFirebaseApp), [.action(.createFirebaseApp, on: .createFirebaseApp, result: .failure, parameters: platform)])
        XCTAssertEqual(analytics.actions(of: .updateNickname), [.action(.updateNickname, on: .firebaseAppDetail, result: .failure, parameters: platform)])
        XCTAssertEqual(analytics.actions(of: .deleteFirebaseApp), [.action(.deleteFirebaseApp, on: .firebaseAppList, result: .failure, parameters: platform)])
    }

    // MARK: - Remote Config

    func testRemoteConfigPublishTracksTapAndFailureWithCountsOnly() async {
        let sut = RemoteConfigViewModel(project: project, account: firebaseAccount, keychain: MockKeyStorable(), analytics: analytics)

        await sut.saveTemplate()

        XCTAssertEqual(analytics.taps(of: .publish), [.buttonTap(.publish, on: .remoteConfig)])
        XCTAssertEqual(analytics.actions(of: .publishRemoteConfig), [
            .action(.publishRemoteConfig, on: .remoteConfig, result: .failure, parameters: [
                AnalyticsParameterKey.count: .int(0),
                AnalyticsParameterKey.conditionCount: .int(0)
            ])
        ])
    }

    func testRemoteConfigRefreshTracksFailureWithoutCredentials() async {
        let sut = RemoteConfigViewModel(project: project, account: firebaseAccount, keychain: MockKeyStorable(), analytics: analytics)

        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .remoteConfig, result: .failure)])
    }

    // MARK: - Messaging

    private func makeMessagingSUT(storage: MockPersistentStorable = MockPersistentStorable()) -> MessagingViewModel {
        MessagingViewModel(project: project, account: firebaseAccount, keychain: MockKeyStorable(), storage: storage, analytics: analytics)
    }

    func testSendCampaignTracksTapAndFailureWithTargetTypeOnly() async {
        let sut = makeMessagingSUT()
        var draft = CampaignDraft()
        draft.title = "Private title"
        draft.body = "Private body"
        draft.topic = "secret-topic"

        await sut.sendCampaign(draft)

        XCTAssertEqual(analytics.taps(of: .send), [.buttonTap(.send, on: .newCampaign)])
        XCTAssertEqual(analytics.actions(of: .sendCampaign), [
            .action(.sendCampaign, on: .newCampaign, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string(CampaignTarget.topic.rawValue)
            ])
        ])
    }

    func testSendInvalidCampaignTracksTapOnly() async {
        let sut = makeMessagingSUT()

        await sut.sendCampaign(CampaignDraft())

        XCTAssertEqual(analytics.taps(of: .send).count, 1)
        XCTAssertTrue(analytics.actions(of: .sendCampaign).isEmpty)
    }

    func testDeleteCampaignTracksSuccessOffline() async {
        let sut = makeMessagingSUT()
        let record = CampaignRecord(
            id: "c1",
            title: "T",
            body: "B",
            imageURL: nil,
            targetType: .topic,
            targetValue: "topic",
            analyticsLabel: nil,
            messageIds: [],
            sentAt: Date(),
            status: .sent,
            sentCount: 1,
            failedCount: 0
        )
        sut.uiState.campaigns = [record]

        await sut.deleteCampaign(record)

        XCTAssertEqual(analytics.actions(of: .deleteCampaign), [.action(.deleteCampaign, on: .messaging, result: .success)])
    }

    // MARK: - Google Play

    private func makePlaySUT(storage: MockPersistentStorable = MockPersistentStorable()) -> GooglePlayAppListViewModel {
        GooglePlayAppListViewModel(
            account: AccountModel(name: "Play", providerType: .googlePlay),
            keychain: MockKeyStorable(),
            storage: storage,
            analytics: analytics
        )
    }

    func testPlayRefreshTracksFailureWithoutCredentials() async {
        let sut = makePlaySUT()

        await sut.load()
        await sut.refresh()

        XCTAssertEqual(analytics.trackedEvents, [.action(.refresh, on: .googlePlayAppList, result: .failure)])
    }

    func testPlayAddAppTracksTapAndFailureWithoutCredentials() async {
        let sut = makePlaySUT()

        await sut.addApp(packageName: "com.example.secret")

        XCTAssertEqual(analytics.taps(of: .add), [.buttonTap(.add, on: .addGooglePlayApp)])
        XCTAssertEqual(analytics.actions(of: .addGooglePlayApp), [.action(.addGooglePlayApp, on: .addGooglePlayApp, result: .failure)])
    }

    func testPlayAddDuplicateAppTracksTapOnly() async {
        let sut = makePlaySUT()
        sut.uiState.apps = [GooglePlayAppItem(id: "com.example.app", packageName: "com.example.app", title: nil, isManuallyAdded: true)]

        await sut.addApp(packageName: "com.example.app")

        XCTAssertEqual(analytics.taps(of: .add).count, 1)
        XCTAssertTrue(analytics.actions(of: .addGooglePlayApp).isEmpty)
    }

    func testPlayRemoveAppTracksTapAndSuccessOffline() async {
        let sut = makePlaySUT()
        let app = GooglePlayAppItem(id: "com.example.app", packageName: "com.example.app", title: nil, isManuallyAdded: true)
        sut.uiState.apps = [app]

        await sut.removeApp(app)

        XCTAssertEqual(analytics.taps(of: .remove), [.buttonTap(.remove, on: .googlePlayAppList)])
        XCTAssertEqual(analytics.actions(of: .removeGooglePlayApp), [.action(.removeGooglePlayApp, on: .googlePlayAppList, result: .success)])
    }
}
