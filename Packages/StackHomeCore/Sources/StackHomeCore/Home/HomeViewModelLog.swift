import Foundation

#if canImport(os)
import os
#endif

/// Foundation-pure logging shim for the core Home view model.
///
/// On Apple platforms this routes through `os.Logger`; on the Windows toolchain
/// (no `os` module) it is a no-op. Gated under `#if canImport(os)` so core
/// imports nothing Apple-only unconditionally (US-010 AC-4) while keeping
/// diagnostics on iOS.
enum HomeViewModelLog {
    static func error(_ message: String) {
        #if canImport(os)
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "StackHomeCore", category: "Home")
            .error("\(message, privacy: .public)")
        #endif
    }
}
