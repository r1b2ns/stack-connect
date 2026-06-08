import XCTest
@testable import WindowsAppCore

/// Unit tests for `WindowsClipboard` (T-F15).
///
/// The Win32 clipboard APIs are only available on Windows, so on the macOS
/// development host we can only verify the non-Windows stub behavior. The
/// Windows-specific path is exercised by the VM-based E2E smoke tests.
final class WindowsClipboardTests: XCTestCase {

    // MARK: - Non-Windows stub (macOS host)

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
}
