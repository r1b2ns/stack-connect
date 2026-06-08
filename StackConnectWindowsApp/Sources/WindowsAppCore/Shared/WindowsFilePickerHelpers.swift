import Foundation

// Phase 4 · Block F · T-F14 — Win32 file picker helper.
//
// Pure, platform-independent helpers extracted from `WindowsFilePicker` so they
// can be unit-tested on the macOS host without WinSDK. The app target's
// `WindowsFilePicker` calls these through a regular `import WindowsAppCore`.

/// Converts a Swift `String` to a null-terminated UTF-16 array suitable for
/// Win32 W-suffix functions.
func wide(_ string: String) -> [UInt16] {
    Array(string.utf16) + [0]
}

/// Builds the Win32 filter string from a Swift-friendly tuple array.
///
/// The Win32 format is pairs of null-terminated UTF-16 strings
/// (`description\0pattern\0`) terminated by a final null character.
/// For example, two filters become:
///
///     "P8 Files (*.p8)\0*.p8\0All Files (*.*)\0*.*\0\0"
///
func buildFilterString(
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
