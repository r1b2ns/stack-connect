import XCTest
@testable import WindowsAppCore

/// Unit tests for the pure file-picker helpers extracted in T-F14.
/// These functions are platform-independent and run on the macOS host.
final class WindowsFilePickerHelpersTests: XCTestCase {

    // MARK: - buildFilterString

    func testBuildFilterStringWithSingleFilter() {
        // Given
        let filters: [(description: String, pattern: String)] = [
            ("desc", "pattern"),
        ]

        // When
        let result = buildFilterString(filters)

        // Then: desc\0pattern\0\0
        let expected: [UInt16] = Array("desc".utf16) + [0]
                                + Array("pattern".utf16) + [0]
                                + [0]
        XCTAssertEqual(result, expected)
    }

    func testBuildFilterStringWithTwoFilters() {
        // Given
        let filters: [(description: String, pattern: String)] = [
            ("d1", "p1"),
            ("d2", "p2"),
        ]

        // When
        let result = buildFilterString(filters)

        // Then: d1\0p1\0d2\0p2\0\0
        let expected: [UInt16] = Array("d1".utf16) + [0]
                                + Array("p1".utf16) + [0]
                                + Array("d2".utf16) + [0]
                                + Array("p2".utf16) + [0]
                                + [0]
        XCTAssertEqual(result, expected)
    }

    func testBuildFilterStringWithEmptyList() {
        // Given
        let filters: [(description: String, pattern: String)] = []

        // When
        let result = buildFilterString(filters)

        // Then: only the final null terminator
        XCTAssertEqual(result, [0])
    }

    // MARK: - wide

    func testWideWithASCIIString() {
        // Given
        let input = "Hello"

        // When
        let result = wide(input)

        // Then: correct UTF-16 code units + null terminator
        let expected: [UInt16] = Array("Hello".utf16) + [0]
        XCTAssertEqual(result, expected)
        // Verify the null terminator is present at the end
        XCTAssertEqual(result.last, 0)
        XCTAssertEqual(result.count, 6) // 5 characters + 1 null
    }

    func testWideWithEmptyString() {
        // Given
        let input = ""

        // When
        let result = wide(input)

        // Then: only the null terminator
        XCTAssertEqual(result, [0])
    }
}
