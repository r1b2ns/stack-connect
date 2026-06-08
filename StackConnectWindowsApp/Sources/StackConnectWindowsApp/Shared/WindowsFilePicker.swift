// Phase 4 · Block F · T-F14 — Win32 file picker helper.
import Foundation
import WindowsAppCore

#if os(Windows)
import WinSDK
#endif

/// Wraps the Win32 `GetOpenFileNameW` dialog behind a simple Swift API.
///
/// Usage:
/// ```swift
/// let path = WindowsFilePicker.openFile(
///     title: "Select Private Key",
///     filters: [
///         ("Auth Key Files (*.p8)", "*.p8"),
///         ("All Files (*.*)", "*.*"),
///     ]
/// )
/// ```
///
/// On macOS (host builds) the function returns `nil` immediately — this stub
/// exists solely so the package compiles on the development host. The real
/// dialog is only shown on Windows.
enum WindowsFilePicker {

    /// Opens a native file-open dialog with the given title and file-type
    /// filters.
    ///
    /// - Parameters:
    ///   - title: The dialog window title.
    ///   - filters: An array of `(description, pattern)` pairs.
    ///     `description` is the human-readable label (e.g. `"JSON Files (*.json)"`)
    ///     and `pattern` is the Win32 wildcard (e.g. `"*.json"`). Multiple
    ///     patterns can be separated by semicolons (e.g. `"*.jpg;*.png"`).
    /// - Returns: The absolute path of the selected file, or `nil` if the user
    ///   cancelled or an error occurred.
    static func openFile(
        title: String,
        filters: [(description: String, pattern: String)]
    ) -> String? {
        #if os(Windows)
        return openFileWin32(title: title, filters: filters)
        #else
        // macOS host stub — file picking is not needed during host development.
        return nil
        #endif
    }
}

// MARK: - Win32 implementation

#if os(Windows)
private extension WindowsFilePicker {

    static func openFileWin32(
        title: String,
        filters: [(description: String, pattern: String)]
    ) -> String? {
        // Buffer to receive the selected file path. MAX_PATH (260) is the
        // classic limit; for v1 this is sufficient.
        let bufferSize = Int(MAX_PATH)
        var fileBuffer = [UInt16](repeating: 0, count: bufferSize)

        var titleW = wide(title)
        var filterW = buildFilterString(filters)

        var ofn = OPENFILENAMEW()
        ofn.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
        ofn.hwndOwner = nil
        ofn.nMaxFile = DWORD(bufferSize)

        // Flags:
        // OFN_FILEMUSTEXIST  — the user cannot type a non-existent path.
        // OFN_PATHMUSTEXIST  — the directory part of the path must exist.
        // OFN_NOCHANGEDIR    — restore the process working directory after the
        //                      dialog closes (prevents side-effects).
        ofn.Flags = DWORD(OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR)

        // The three buffers (file, title, filter) must all remain pinned for
        // the duration of the GetOpenFileNameW call, because the OPENFILENAMEW
        // struct holds raw pointers into each of them. The triple nesting
        // ensures all three withUnsafeMutableBufferPointer scopes overlap,
        // keeping every buffer alive and addressable simultaneously.
        let result: Bool = fileBuffer.withUnsafeMutableBufferPointer { fileBuf in
            titleW.withUnsafeBufferPointer { titleBuf in
                filterW.withUnsafeBufferPointer { filterBuf in
                    ofn.lpstrFile = fileBuf.baseAddress
                    ofn.lpstrTitle = titleBuf.baseAddress
                    ofn.lpstrFilter = filterBuf.baseAddress
                    return GetOpenFileNameW(&ofn)
                }
            }
        }

        // When GetOpenFileNameW returns false it can mean either a user
        // cancellation (CommDlgExtendedError() == 0) or a real error
        // (CommDlgExtendedError() != 0). For v1 we treat both as "no file
        // selected"; callers needing richer diagnostics can check
        // CommDlgExtendedError() here.
        guard result else { return nil }

        // Convert the null-terminated UTF-16 buffer back to a Swift String.
        return String(decodingCString: fileBuffer, as: UTF16.self)
    }
}
#endif
