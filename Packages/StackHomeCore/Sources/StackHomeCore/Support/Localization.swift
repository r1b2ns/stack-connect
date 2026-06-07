import Foundation

/// Returns a localized string for `key`, compiling on both Apple platforms and
/// the Windows/Linux port.
///
/// `String(localized:)` is only available in Apple's Foundation, not in
/// swift-corelibs-foundation used by the Windows/Linux toolchain. On Apple
/// platforms this funnels through `String(localized:)` so existing String
/// Catalog / `.strings` lookups keep working; elsewhere it falls back to
/// `NSLocalizedString`, which resolves to the key itself when no translation
/// table is present.
func localizedString(_ key: String) -> String {
    #if canImport(Darwin)
    return String(localized: String.LocalizationValue(key))
    #else
    return NSLocalizedString(key, comment: "")
    #endif
}
