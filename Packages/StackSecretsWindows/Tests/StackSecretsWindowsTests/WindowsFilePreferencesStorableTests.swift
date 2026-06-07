import XCTest
import StackHomeCore
@testable import StackSecretsWindows

/// Exercises the `KeyStorable` contract for the JSON-file prefs store. On the
/// macOS host these run against an injected temp directory; on Windows the same
/// assertions cover the real `%APPDATA%\StackConnect\` path (validated on the
/// Block E VM). Each test uses a fresh temp directory to avoid cross-test bleed.
///
/// Coverage map:
/// - TC-060 — `[HomeWidgetConfiguration]` round-trips via the `KeyStorable`
///   Codable convenience (`setObject`/`object`).
/// - TC-061 — prefs persist to a JSON file under the base directory (structural
///   check that the file exists and is valid JSON; the `%APPDATA%` path itself
///   is VM-gated).
/// - TC-079 — restart persistence: a fresh store instance pointed at the same
///   directory reads back previously written config.
final class WindowsFilePreferencesStorableTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("StackConnectPrefsTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeSUT(fileName: String = "prefs.json") -> WindowsFilePreferencesStorable {
        WindowsFilePreferencesStorable(baseDirectory: tempDirectory, fileName: fileName)
    }

    // MARK: - Primitive round-trips

    func test_string_roundTrip() {
        let sut = makeSUT()
        sut.set("hello", forKey: "greeting")
        XCTAssertEqual(sut.string(forKey: "greeting"), "hello")
    }

    func test_int_roundTrip() {
        let sut = makeSUT()
        sut.set(42, forKey: "answer")
        XCTAssertEqual(sut.int(forKey: "answer"), 42)
    }

    func test_double_roundTrip() {
        let sut = makeSUT()
        sut.set(3.14159, forKey: "pi")
        XCTAssertEqual(sut.double(forKey: "pi"), 3.14159)
    }

    func test_bool_roundTrip() {
        let sut = makeSUT()
        sut.set(true, forKey: "flag")
        XCTAssertEqual(sut.bool(forKey: "flag"), true)

        sut.set(false, forKey: "flag")
        XCTAssertEqual(sut.bool(forKey: "flag"), false)
    }

    func test_data_roundTrip() {
        let sut = makeSUT()
        let payload = Data([0x00, 0x01, 0xFF, 0x7F, 0x80])
        sut.set(payload, forKey: "blob")
        XCTAssertEqual(sut.data(forKey: "blob"), payload)
    }

    // MARK: - TC-060 — HomeWidgetConfiguration round-trip

    func test_homeWidgetConfigurations_roundTrip() {
        let sut = makeSUT()
        let config: [HomeWidgetConfiguration] = [
            HomeWidgetConfiguration(kind: .inReview, size: .expanded),
            HomeWidgetConfiguration(kind: .awaitingRelease, size: .compact),
            HomeWidgetConfiguration(kind: .recentReviews, size: .expanded),
        ]

        sut.setObject(config, forKey: "home.widget.configurations")
        let read: [HomeWidgetConfiguration]? = sut.object(forKey: "home.widget.configurations")

        XCTAssertEqual(read, config)
    }

    // MARK: - TC-061 — persisted to a JSON file under the base directory

    func test_persistsToJSONFileOnDisk() throws {
        let sut = makeSUT(fileName: "prefs.json")
        sut.set("value", forKey: "key")

        let fileURL = tempDirectory.appendingPathComponent("prefs.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.path),
            "Prefs must be persisted to a JSON file in the base directory"
        )

        // The file must be syntactically valid JSON.
        let data = try Data(contentsOf: fileURL)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    // MARK: - TC-079 — restart persistence (fresh instance, same directory)

    func test_restartPersistence_freshInstanceReadsPreviousConfig() {
        let config: [HomeWidgetConfiguration] = [
            HomeWidgetConfiguration(kind: .recentReviews, size: .compact),
        ]

        // First "session" writes and is discarded.
        do {
            let writer = makeSUT()
            writer.setObject(config, forKey: "home.widget.configurations")
        }

        // Second "session": a brand-new instance pointed at the same directory.
        let reader = makeSUT()
        let read: [HomeWidgetConfiguration]? = reader.object(forKey: "home.widget.configurations")

        XCTAssertEqual(read, config)
    }

    func test_restartPersistence_freshInstanceReadsPrimitive() {
        do {
            let writer = makeSUT()
            writer.set("persisted", forKey: "k")
        }
        let reader = makeSUT()
        XCTAssertEqual(reader.string(forKey: "k"), "persisted")
    }

    // MARK: - Delete / missing-key

    func test_missingKey_returnsNil() {
        let sut = makeSUT()
        XCTAssertNil(sut.string(forKey: "absent"))
        XCTAssertNil(sut.int(forKey: "absent"))
        XCTAssertNil(sut.double(forKey: "absent"))
        XCTAssertNil(sut.bool(forKey: "absent"))
        XCTAssertNil(sut.data(forKey: "absent"))
        let object: [HomeWidgetConfiguration]? = sut.object(forKey: "absent")
        XCTAssertNil(object)
    }

    func test_removeObject_deletesValue() {
        let sut = makeSUT()
        sut.set("temp", forKey: "scratch")
        XCTAssertNotNil(sut.string(forKey: "scratch"))

        sut.removeObject(forKey: "scratch")
        XCTAssertNil(sut.string(forKey: "scratch"))
    }

    func test_setNil_removesValue() {
        let sut = makeSUT()
        sut.set("temp", forKey: "scratch")
        sut.set(nil, forKey: "scratch")
        XCTAssertNil(sut.string(forKey: "scratch"))
    }

    func test_overwrite_replacesValue() {
        let sut = makeSUT()
        sut.set("first", forKey: "k")
        sut.set("second", forKey: "k")
        XCTAssertEqual(sut.string(forKey: "k"), "second")
    }

    // MARK: - Multiple keys coexist in the same file

    func test_multipleKeys_coexist() {
        let sut = makeSUT()
        sut.set("a", forKey: "first")
        sut.set(7, forKey: "second")
        sut.set(true, forKey: "third")

        XCTAssertEqual(sut.string(forKey: "first"), "a")
        XCTAssertEqual(sut.int(forKey: "second"), 7)
        XCTAssertEqual(sut.bool(forKey: "third"), true)
    }

    /// A value stored as one type must not be misread as a different primitive.
    func test_typeMismatch_returnsNil() {
        let sut = makeSUT()
        sut.set("not a number", forKey: "k")
        XCTAssertNil(sut.int(forKey: "k"))
        XCTAssertNil(sut.bool(forKey: "k"))
        XCTAssertNil(sut.data(forKey: "k"))
    }
}
