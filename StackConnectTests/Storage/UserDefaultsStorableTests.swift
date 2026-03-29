import XCTest
@testable import StackConnect

final class UserDefaultsStorableTests: XCTestCase {

    private var sut: UserDefaultsStorable!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "UserDefaultsStorableTests")!
        defaults.removePersistentDomain(forName: "UserDefaultsStorableTests")
        sut = UserDefaultsStorable(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "UserDefaultsStorableTests")
        defaults = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - String

    func testStringReadWrite() {
        XCTAssertNil(sut.string(forKey: "key"))
        sut.set("hello", forKey: "key")
        XCTAssertEqual(sut.string(forKey: "key"), "hello")
    }

    // MARK: - Int

    func testIntReadWrite() {
        XCTAssertNil(sut.int(forKey: "key"))
        sut.set(42, forKey: "key")
        XCTAssertEqual(sut.int(forKey: "key"), 42)
    }

    // MARK: - Double

    func testDoubleReadWrite() {
        XCTAssertNil(sut.double(forKey: "key"))
        sut.set(3.14, forKey: "key")
        XCTAssertEqual(sut.double(forKey: "key")!, 3.14, accuracy: 0.001)
    }

    // MARK: - Bool

    func testBoolReadWrite() {
        XCTAssertNil(sut.bool(forKey: "key"))
        sut.set(true, forKey: "key")
        XCTAssertEqual(sut.bool(forKey: "key"), true)
    }

    // MARK: - Data

    func testDataReadWrite() {
        let data = Data([0x01, 0x02, 0x03])
        XCTAssertNil(sut.data(forKey: "key"))
        sut.set(data, forKey: "key")
        XCTAssertEqual(sut.data(forKey: "key"), data)
    }

    // MARK: - Codable

    func testCodableReadWrite() {
        struct Dummy: Codable, Equatable {
            let name: String
            let value: Int
        }
        let obj = Dummy(name: "test", value: 99)
        sut.setObject(obj, forKey: "key")
        let result: Dummy? = sut.object(forKey: "key")
        XCTAssertEqual(result, obj)
    }

    // MARK: - Remove

    func testRemoveObject() {
        sut.set("value", forKey: "key")
        XCTAssertNotNil(sut.string(forKey: "key"))
        sut.removeObject(forKey: "key")
        XCTAssertNil(sut.string(forKey: "key"))
    }
}
