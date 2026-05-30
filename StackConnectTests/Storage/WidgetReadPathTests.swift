import XCTest
import SwiftData
import StackCore
@testable import StackConnect

/// Reproduces the exact read path the widget extension uses: save the app's real
/// models, then read them back through the typeName-based overloads into focused
/// DTOs (as the widget does). Pinpoints why the iOS widget's Awaiting Release is
/// empty while the app shows the app.
final class WidgetReadPathTests: XCTestCase {

    private func makeStorage() throws -> SwiftDataStorable {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistedItem.self, configurations: config)
        return SwiftDataStorable.make(modelContainer: container)
    }

    private struct PhasedDTO: Codable {
        let id: String
        var state: String?
        var currentDayNumber: Int?
    }

    private struct AppDTO: Codable {
        let id: String
        let name: String
        var appStoreState: String?
    }

    func testFetchPhasedViaTypeName() async throws {
        let storage = try makeStorage()
        let phased = PhasedReleaseModel(
            id: "rel1",
            state: .active,
            startDate: Date(),
            totalPauseDuration: 0,
            currentDayNumber: 2
        )
        try await storage.save(phased, id: "phased.app1")

        let fetched = try await storage.fetch(PhasedDTO.self, id: "phased.app1", typeName: "PhasedReleaseModel")
        XCTAssertNotNil(fetched, "Widget phased fetch returned nil — root cause of empty Awaiting Release")
        XCTAssertEqual(fetched?.state, "ACTIVE")
        XCTAssertEqual(fetched?.currentDayNumber, 2)
    }

    func testFetchAppStateViaTypeName() async throws {
        let storage = try makeStorage()
        let app = AppModel(
            id: "app1",
            name: "My App",
            bundleId: "com.example",
            accountId: "acc1",
            appStoreState: .readyForSale
        )
        try await storage.save(app, id: app.id)

        let apps = try await storage.fetchAll(AppDTO.self, typeName: "AppModel")
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.appStoreState, "READY_FOR_SALE")
    }
}
