#if os(Windows)
import WinSDK
#endif

// Phase 4 · Block F · T-F15 / T-W02 — Win32 clipboard helpers.
//
// getText(): Reads Unicode text from the system clipboard using the Win32 API
// sequence: OpenClipboard -> GetClipboardData(CF_UNICODETEXT) -> GlobalLock ->
// String conversion -> GlobalUnlock -> CloseClipboard.
//
// setText(): Writes Unicode text to the system clipboard using the Win32 API
// sequence: OpenClipboard -> EmptyClipboard -> GlobalAlloc(GMEM_MOVEABLE) ->
// GlobalLock -> copy UTF-16 string -> GlobalUnlock ->
// SetClipboardData(CF_UNICODETEXT) -> CloseClipboard.
//
// On non-Windows hosts (macOS) stubs are provided so the package builds on the
// development machine without conditional compilation at call sites.

/// Caseless namespace for clipboard operations.
public enum WindowsClipboard {

    /// Returns the current text content of the system clipboard, or `nil` if the
    /// clipboard is empty, unavailable, or does not contain Unicode text.
    ///
    /// - Important: Win32 clipboard APIs (`OpenClipboard`, `CloseClipboard`, etc.)
    ///   use a per-thread open/close model. The caller must ensure this method is
    ///   invoked on the same thread that owns the clipboard session — typically the
    ///   main (UI) thread. Calling from multiple threads concurrently is undefined
    ///   behavior at the Win32 level.
    public static func getText() -> String? {
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

    /// Writes the given string to the system clipboard as Unicode text.
    ///
    /// - Parameter text: The string to place on the clipboard.
    /// - Returns: `true` if the text was successfully written to the clipboard,
    ///   `false` if any Win32 call failed (or on non-Windows platforms).
    ///
    /// - Important: Same threading constraints as `getText()` — call from the
    ///   thread that owns the clipboard session (typically the main/UI thread).
    public static func setText(_ text: String) -> Bool {
        #if os(Windows)
        // Encode the Swift string as a null-terminated UTF-16 array.
        let utf16Units = wide(text)
        let byteCount = utf16Units.count * MemoryLayout<WCHAR>.size

        guard OpenClipboard(nil) else { return false }
        defer { CloseClipboard() }

        guard EmptyClipboard() else {
            return false
        }

        // Allocate moveable global memory for the clipboard data.
        guard let hMem = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(byteCount)) else {
            return false
        }

        // Lock the memory and copy the UTF-16 data into it.
        guard let lockedPointer = GlobalLock(hMem) else {
            GlobalFree(hMem)
            return false
        }

        utf16Units.withUnsafeBufferPointer { buffer in
            memcpy(lockedPointer, buffer.baseAddress!, byteCount)
        }
        GlobalUnlock(hMem)

        // Transfer ownership of hMem to the clipboard. After a successful
        // SetClipboardData call the system owns the handle — we must NOT free it.
        guard SetClipboardData(UINT(CF_UNICODETEXT), hMem) != nil else {
            // SetClipboardData failed; we still own hMem, so free it.
            GlobalFree(hMem)
            return false
        }

        return true
        #else
        return false
        #endif
    }
}
