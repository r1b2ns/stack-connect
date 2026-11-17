import Foundation
import StackCoreRust

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

extension OfflineError {

    /// True for the local offline guard and for Rust-core transport failures
    /// (any provider) — the cases where cached data is still the best thing to
    /// show and the global offline banner already explains why.
    static func isConnectivityFailure(_ error: Error) -> Bool {
        if case OfflineError.noConnection = error { return true }
        if case StackError.Network = error { return true }
        return false
    }
}
