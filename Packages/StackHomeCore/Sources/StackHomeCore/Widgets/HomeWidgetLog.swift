import Foundation

#if canImport(os)
import os
#endif

/// Foundation-pure logging shim for the core widget data layer.
///
/// On Apple platforms this routes through `os.Logger`; on the Windows toolchain
/// (no `os` module) it is a no-op. Keeping it gated under `#if canImport(os)`
/// preserves the US-010 invariant that core imports nothing Apple-only
/// unconditionally, while retaining diagnostics on iOS.
enum HomeWidgetLog {
    static func error(_ message: String) {
        #if canImport(os)
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "StackHomeCore", category: "Widget")
            .error("\(message, privacy: .public)")
        #endif
    }
}
