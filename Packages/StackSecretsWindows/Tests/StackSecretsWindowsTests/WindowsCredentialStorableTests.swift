import XCTest
@testable import StackSecretsWindows

/// Exercises the `KeyStorable` contract and the `KeychainStorable`-mirroring
/// primitive encoding. On the macOS host these run against the in-memory
/// fallback store; on Windows the same assertions cover the Credential Manager
/// path. Each test uses a fresh instance to avoid cross-test bleed.
final class WindowsCredentialStorableTests: XCTestCase {

    private func makeSUT() -> WindowsCredentialStorable {
        WindowsCredentialStorable(service: "app.stackconnect.tests")
    }

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

    func test_codableObject_roundTrip() {
        struct Credentials: Codable, Equatable {
            let keyID: String
            let issuerID: String
        }
        let sut = makeSUT()
        let value = Credentials(keyID: "ABC123", issuerID: "issuer-1")

        sut.setObject(value, forKey: "asc")
        let read: Credentials? = sut.object(forKey: "asc")
        XCTAssertEqual(read, value)
    }

    func test_missingKey_returnsNil() {
        let sut = makeSUT()
        XCTAssertNil(sut.string(forKey: "absent"))
        XCTAssertNil(sut.int(forKey: "absent"))
        XCTAssertNil(sut.double(forKey: "absent"))
        XCTAssertNil(sut.bool(forKey: "absent"))
        XCTAssertNil(sut.data(forKey: "absent"))
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

    /// A wrong-width blob must not be misread as a primitive.
    func test_typeMismatch_returnsNil() {
        let sut = makeSUT()
        sut.set("not a number", forKey: "k")
        XCTAssertNil(sut.int(forKey: "k"))
        XCTAssertNil(sut.bool(forKey: "k"))
    }
}
