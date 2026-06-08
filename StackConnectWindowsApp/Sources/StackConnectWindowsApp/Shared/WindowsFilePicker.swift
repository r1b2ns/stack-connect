import Foundation

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

    /// Converts a Swift `String` to a null-terminated UTF-16 array suitable for
    /// Win32 W-suffix functions.
    static func wide(_ string: String) -> [UInt16] {
        Array(string.utf16) + [0]
    }

    /// Builds the Win32 filter string from the Swift-friendly tuple array.
    ///
    /// The Win32 format is pairs of null-terminated UTF-16 strings
    /// (`description\0pattern\0`) terminated by a final null character.
    /// For example, two filters become:
    ///
    ///     "P8 Files (*.p8)\0*.p8\0All Files (*.*)\0*.*\0\0"
    ///
    static func buildFilterString(
        _ filters: [(description: String, pattern: String)]
    ) -> [UInt16] {
        var result: [UInt16] = []
        for filter in filters {
            result.append(contentsOf: filter.description.utf16)
            result.append(0) // null terminator between description and pattern
            result.append(contentsOf: filter.pattern.utf16)
            result.append(0) // null terminator between pattern and next pair
        }
        result.append(0) // final double-null terminator
        return result
    }

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

        let result: Bool = fileBuffer.withUnsafeMutableBufferPointer { fileBuf in
            titleW.withUnsafeMutableBufferPointer { titleBuf in
                filterW.withUnsafeMutableBufferPointer { filterBuf in
                    ofn.lpstrFile = fileBuf.baseAddress
                    ofn.lpstrTitle = titleBuf.baseAddress
                    ofn.lpstrFilter = filterBuf.baseAddress
                    return GetOpenFileNameW(&ofn)
                }
            }
        }

        guard result else { return nil }

        // Convert the null-terminated UTF-16 buffer back to a Swift String.
        return String(decodingCString: fileBuffer, as: UTF16.self)
    }
}
#endif
