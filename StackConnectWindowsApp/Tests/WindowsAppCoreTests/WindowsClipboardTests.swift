import XCTest
@testable import WindowsAppCore

/// Unit tests for `WindowsClipboard` (T-F15, T-W02).
///
/// The Win32 clipboard APIs are only available on Windows, so on the macOS
/// development host we can only verify the non-Windows stub behavior. The
/// Windows-specific path is exercised by the VM-based E2E smoke tests.
final class WindowsClipboardTests: XCTestCase {

    // MARK: - getText() · Non-Windows stub (macOS host)

    func testGetTextReturnsNilOnNonWindowsPlatform() {
        #if !os(Windows)
        XCTAssertNil(WindowsClipboard.getText(),
                     "getText() must return nil on non-Windows platforms (stub path)")
        #endif
    }

    func testGetTextIsIdempotentOnNonWindowsPlatform() {
        #if !os(Windows)
        // Calling multiple times should consistently return nil without side effects.
        XCTAssertNil(WindowsClipboard.getText())
        XCTAssertNil(WindowsClipboard.getText())
        #endif
    }

    // MARK: - setText() · Non-Windows stub (macOS host) — TC-073

    func testSetTextReturnsFalseOnNonWindowsPlatform() {
        #if !os(Windows)
        // TC-073: On macOS host, setText must return false (graceful degradation).
        XCTAssertFalse(WindowsClipboard.setText("Hello"),
                       "setText() must return false on non-Windows platforms (stub path)")
        #endif
    }

    func testSetTextReturnsFalseForEmptyStringOnNonWindowsPlatform() {
        #if !os(Windows)
        XCTAssertFalse(WindowsClipboard.setText(""),
                       "setText() must return false even for an empty string on non-Windows platforms")
        #endif
    }

    func testSetTextIsIdempotentOnNonWindowsPlatform() {
        #if !os(Windows)
        // Calling multiple times should consistently return false without side effects.
        XCTAssertFalse(WindowsClipboard.setText("first"))
        XCTAssertFalse(WindowsClipboard.setText("second"))
        #endif
    }

    // MARK: - setText() · Windows path

    #if os(Windows)
    func testSetTextReturnsTrueOnWindows() {
        // Basic smoke test: writing a non-empty string should succeed.
        XCTAssertTrue(WindowsClipboard.setText("StackConnect clipboard test"),
                      "setText() must return true on Windows when the clipboard is available")
    }

    func testSetTextThenGetTextRoundTrip() {
        let testString = "Round-trip test \u{1F680}" // includes a multi-code-unit emoji
        let didSet = WindowsClipboard.setText(testString)
        XCTAssertTrue(didSet)
        let retrieved = WindowsClipboard.getText()
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved, testString,
                       "getText() must return the exact string previously set via setText()")
    }

    func testSetTextEmptyStringOnWindows() {
        // An empty string is valid clipboard content.
        XCTAssertTrue(WindowsClipboard.setText(""),
                      "setText() must succeed with an empty string on Windows")
    }
    #endif
}
