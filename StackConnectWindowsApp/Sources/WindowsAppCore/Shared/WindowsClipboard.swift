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

    /// Returns the current text content of the system clipboard, or `nil` if the
    /// clipboard is empty, unavailable, or does not contain Unicode text.
    ///
    /// - Important: Win32 clipboard APIs (`OpenClipboard`, `CloseClipboard`, etc.)
    ///   use a per-thread open/close model. The caller must ensure this method is
    ///   invoked on the same thread that owns the clipboard session — typically the
    ///   main (UI) thread. Calling from multiple threads concurrently is undefined
    ///   behavior at the Win32 level.
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
