import Foundation
import os
import StackCoreRust

/// Forwards the Rust core's diagnostic lines (`CoreLogger`, see the core's
/// `docs/LOGGING.md`) to the unified log: subsystem `Log.subsystem`, category
/// `core.<target>` (`core.http`, `core.auth`, `core.googleplay.users`, …), so
/// Console.app and `log stream` can filter by area.
///
/// Every message is redacted by the core before it gets here (no token, key or
/// JWT; e-mails masked), so it is logged `privacy: .public`; without that the
/// unified log shows `<private>` outside Xcode.
///
/// The core calls `log` synchronously on whichever thread it runs on (a tokio
/// worker for async calls), so it only hands the line to `os.Logger` and never
/// calls back into the core.
final class RustCoreLogger: CoreLogger {

    private let subsystem: String
    /// One `Logger` per target, built on first use.
    private let loggers = OSAllocatedUnfairLock<[String: Logger]>(initialState: [:])

    init(subsystem: String = Log.subsystem) {
        self.subsystem = subsystem
    }

    func log(level: LogLevel, target: String, message: String) {
        logger(for: target).log(level: Self.osLogType(for: level), "\(message, privacy: .public)")
    }

    // MARK: - Mapping

    /// The unified-log category of a core target.
    static func category(for target: String) -> String {
        "core.\(target)"
    }

    /// The unified-log type of a core level, one distinct type per level:
    /// - `error` (5xx, transport failure) → `.error`;
    /// - `warn` (4xx, local validation, failed cleanup) → `.default` (notice).
    ///   Not `Logger.warning`, which `os` logs at `.error`: it would make a
    ///   refused request indistinguishable from a broken one;
    /// - `info` (writes, totals, 401 retries) → `.info`;
    /// - `debug` (one line per request, paging, token minting) → `.debug`.
    static func osLogType(for level: LogLevel) -> OSLogType {
        switch level {
        case .error: return .error
        case .warn: return .default
        case .info: return .info
        case .debug: return .debug
        }
    }

    // MARK: - Private

    private func logger(for target: String) -> Logger {
        loggers.withLock { cache in
            if let logger = cache[target] { return logger }
            let logger = Logger(subsystem: subsystem, category: Self.category(for: target))
            cache[target] = logger
            return logger
        }
    }
}

/// Installs `RustCoreLogger` as the core's process-wide log sink, once.
///
/// Call `install()` at startup, before the first `connect`. Later calls are
/// no-ops, so a second install never replaces the sink or its level. Safe in
/// the fake data mode and in tests: `setCoreLogger` is a plain call into the
/// core that only stores the sink, and the fakes never reach the core's HTTP
/// layer, so they simply produce no core lines.
final class CoreLoggerInstaller: Sendable {

    static let shared = CoreLoggerInstaller()

    /// The most verbose level the core delivers: `.debug` in DEBUG builds,
    /// `.info` in Release (one line per request is too chatty to keep on).
    static var defaultMinLevel: LogLevel {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }

    private let setLogger: @Sendable (CoreLogger, LogLevel) -> Void
    private let installed = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// - Parameter setLogger: hands the sink to the core; injectable for tests.
    init(setLogger: @escaping @Sendable (CoreLogger, LogLevel) -> Void = { setCoreLogger(logger: $0, minLevel: $1) }) {
        self.setLogger = setLogger
    }

    /// Installs the sink on the first call; returns `false` (and does nothing)
    /// on every later one.
    @discardableResult
    func install(
        minLevel: LogLevel = CoreLoggerInstaller.defaultMinLevel,
        logger: @autoclosure () -> CoreLogger = RustCoreLogger()
    ) -> Bool {
        let isFirst = installed.withLock { isInstalled in
            defer { isInstalled = true }
            return !isInstalled
        }
        guard isFirst else { return false }
        setLogger(logger(), minLevel)
        Log.print.info("[CoreLog] Core diagnostic logs forwarded to os.Logger (min level: \(String(describing: minLevel), privacy: .public))")
        return true
    }
}
