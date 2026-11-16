import XCTest
import StackProtocols
@testable import StackConnect

/// Analytics coverage for the device list / detail / bulk-import ViewModels.
@MainActor
final class DevicesViewModelsTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private let account = AccountModel(name: "Team", providerType: .apple)
    private let device = DeviceModel(
        id: "device-1",
        name: "Ada's iPhone",
        udid: "00008030-001A2C3E0C38802E",
        platform: "IOS",
        deviceClass: "IPHONE",
        model: nil,
        status: "ENABLED",
        addedDate: nil
    )

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - DevicesList

    func testListLoadTracksNothingAndRefreshTracksFailure() async {
        let sut = DevicesListViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .devicesList, result: .failure)])
    }

    func testRegisterTracksTapAndPlatformOnly() async {
        let sut = DevicesListViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)

        _ = await sut.create(name: "Ada's iPhone", platformRaw: "IOS", udid: "00008030-001A2C3E0C38802E")

        XCTAssertEqual(analytics.taps(of: .register), [.buttonTap(.register, on: .createDevice)])
        XCTAssertEqual(analytics.actions(of: .registerDevice), [
            .action(.registerDevice, on: .createDevice, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string("IOS")
            ])
        ])
    }

    // MARK: - DeviceDetail

    func testRenameAndToggleStatusTrackTapAndFailureWithoutCredentials() async {
        let sut = DeviceDetailViewModel(account: account, device: device, keychain: MockKeyStorable(), analytics: analytics)

        _ = await sut.rename(to: "Renamed")
        await sut.toggleStatus()

        XCTAssertEqual(analytics.taps(of: .save), [.buttonTap(.save, on: .deviceDetail)])
        XCTAssertEqual(analytics.taps(of: .toggleStatus), [.buttonTap(.toggleStatus, on: .deviceDetail)])
        XCTAssertEqual(analytics.actions(of: .renameDevice), [.action(.renameDevice, on: .deviceDetail, result: .failure)])
        XCTAssertEqual(analytics.actions(of: .toggleDeviceStatus), [
            .action(.toggleDeviceStatus, on: .deviceDetail, result: .failure, parameters: [
                AnalyticsParameterKey.enabled: .bool(false)
            ])
        ])
    }

    // MARK: - ImportDevices

    func testLoadFileTracksSuccessWithCountAndFailure() async throws {
        let sut = ImportDevicesViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("analytics-test-\(UUID().uuidString).txt")
        try "00008030-001A2C3E0C38802E\tiPhone A\n00008030-001A2C3E0C38802F\tiPhone B\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        await sut.loadFile(from: url)
        let parsedCount = sut.uiState.parsed.count
        await sut.loadFile(from: url.appendingPathExtension("missing"))

        XCTAssertEqual(analytics.actions(of: .loadDevicesFile), [
            .action(.loadDevicesFile, on: .importDevices, result: .success, parameters: [
                AnalyticsParameterKey.count: .int(parsedCount)
            ]),
            .action(.loadDevicesFile, on: .importDevices, result: .failure)
        ])
    }

    func testStartImportTracksTapAndFailureWithoutCredentials() async throws {
        let sut = ImportDevicesViewModel(account: account, keychain: MockKeyStorable(), analytics: analytics)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("analytics-test-\(UUID().uuidString).txt")
        try "00008030-001A2C3E0C38802E\tiPhone A\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        await sut.loadFile(from: url)
        sut.uiState.selectedIds = Set(sut.uiState.parsed.map(\.id))

        await sut.startImport()

        XCTAssertEqual(analytics.taps(of: .register), [.buttonTap(.register, on: .importDevices)])
        XCTAssertEqual(analytics.actions(of: .importDevices), [
            .action(.importDevices, on: .importDevices, result: .failure, parameters: [
                AnalyticsParameterKey.count: .int(sut.uiState.parsed.count)
            ])
        ])
    }
}
