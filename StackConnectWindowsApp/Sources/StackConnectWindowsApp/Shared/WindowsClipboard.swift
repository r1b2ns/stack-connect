import Foundation

#if os(Windows)
import WinSDK
#endif

// Phase 4 · Block F · T-F15 — Win32 clipboard paste helper.
//
// Reads Unicode text from the system clipboard using the Win32 API sequence:
// OpenClipboard -> GetClipboardData(CF_UNICODETEXT) -> GlobalLock -> String
// conversion -> GlobalUnlock -> CloseClipboard.
//
// On non-Windows hosts (macOS) a stub returning nil is provided so the package
// builds on the development machine without conditional compilation at call sites.

/// Caseless namespace for clipboard operations.
enum WindowsClipboard {

    /// Returns the current text content of the system clipboard, or nil if the
    /// clipboard is empty, unavailable, or does not contain Unicode text.
    static func getText() -> String? {
        #if os(Windows)
        guard OpenClipboard(nil) else { return nil }
        defer { CloseClipboard() }

        guard let handle = GetClipboardData(UINT(CF_UNICODETEXT)) else {
            return nil
        }

        guard let pointer = GlobalLock(handle) else {
            return nil
        }
        defer { GlobalUnlock(handle) }

        let widePointer = pointer.assumingMemoryBound(to: WCHAR.self)
        return String(decodingCString: widePointer, as: UTF16.self)
        #else
        return nil
        #endif
    }
}
