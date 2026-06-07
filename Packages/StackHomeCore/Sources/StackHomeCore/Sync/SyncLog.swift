import Foundation

#if canImport(os)
import os
#endif

/// Foundation-pure logging shim for the core sync pipeline.
///
/// On Apple platforms this routes through `os.Logger`; on the Windows toolchain
/// (no `os` module) it is a no-op. Gating it behind `#if canImport(os)` keeps the
/// US-010 invariant that core imports nothing Apple-only unconditionally, while
/// preserving the same diagnostics the iOS `SyncService` emitted via `Log.print`.
enum SyncLog {

    #if canImport(os)
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "StackHomeCore",
        category: "Sync"
    )
    #endif

    static func info(_ message: String) {
        #if canImport(os)
        logger.info("\(message, privacy: .public)")
        #endif
    }

    static func notice(_ message: String) {
        #if canImport(os)
        logger.notice("\(message, privacy: .public)")
        #endif
    }

    static func error(_ message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #endif
    }
}
