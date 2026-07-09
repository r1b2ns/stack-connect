import Foundation

/// Thrown by write/mutating operations that require the network when the device
/// is offline.
///
/// Conforms to `LocalizedError` with friendly copy so the existing error
/// surfaces in ViewModels (`error.localizedDescription`, or the
/// `AppleAPIErrorTranslator.friendlyMessage` fallback) show the right message
/// with no per-ViewModel changes.
enum OfflineError: LocalizedError {
    case noConnection

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return String(localized: "No internet connection. This action isn't available offline.")
        }
    }
}
