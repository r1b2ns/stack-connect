import XCTest
import os
import StackCoreRust
@testable import StackConnect

/// `RustCoreLogger` maps the core's levels and targets onto the unified log,
/// and `CoreLoggerInstaller` hands it to the core exactly once.
final class RustCoreLoggerTests: XCTestCase {

    // MARK: - Mapping

    func testEachCoreLevelMapsToItsOwnLogType() {
        XCTAssertEqual(RustCoreLogger.osLogType(for: .error), .error)
        XCTAssertEqual(RustCoreLogger.osLogType(for: .warn), .default, "Not .error: a refused request isn't a broken one")
        XCTAssertEqual(RustCoreLogger.osLogType(for: .info), .info)
        XCTAssertEqual(RustCoreLogger.osLogType(for: .debug), .debug)

        let types = [LogLevel.error, .warn, .info, .debug].map { RustCoreLogger.osLogType(for: $0).rawValue }
        XCTAssertEqual(Set(types).count, 4, "Levels stay distinguishable in Console")
    }

    func testTheCategoryIsTheTargetUnderCore() {
        XCTAssertEqual(RustCoreLogger.category(for: "http"), "core.http")
        XCTAssertEqual(RustCoreLogger.category(for: "googleplay.users"), "core.googleplay.users")
    }

    func testLoggingEveryLevelAndTargetIsSafeFromAnyThread() {
        let logger = RustCoreLogger(subsystem: "zeroSixteen.stackconnect.tests")
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            let level = [LogLevel.error, .warn, .info, .debug][index % 4]
            logger.log(level: level, target: ["http", "auth", "googleplay.users"][index % 3], message: "line \(index)")
        }
    }

    func testTheDefaultMinLevelIsDebugInDebugBuilds() {
        #if DEBUG
        XCTAssertEqual(CoreLoggerInstaller.defaultMinLevel, .debug)
        #else
        XCTAssertEqual(CoreLoggerInstaller.defaultMinLevel, .info)
        #endif
    }

    // MARK: - Installing

    func testInstallingHandsTheLoggerToTheCoreOnce() {
        let spy = SetLoggerSpy()
        let installer = CoreLoggerInstaller(setLogger: spy.record)
        let logger = RustCoreLogger()

        XCTAssertTrue(installer.install(minLevel: .info, logger: logger))
        XCTAssertFalse(installer.install(minLevel: .debug, logger: RustCoreLogger()), "A second install is a no-op")
        XCTAssertFalse(installer.install())

        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertTrue(spy.calls.first?.logger === logger)
        XCTAssertEqual(spy.calls.first?.minLevel, .info, "The first level stays")
    }

    func testConcurrentInstallsHandTheLoggerToTheCoreOnce() {
        let spy = SetLoggerSpy()
        let installer = CoreLoggerInstaller(setLogger: spy.record)

        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            installer.install()
        }

        XCTAssertEqual(spy.calls.count, 1)
    }

    func testTheSharedInstallerWasInstalledAtLaunchAndIsIdempotent() {
        // The test host's `StackConnectApp.init` already installed the real sink
        // into the real core; installing again changes nothing and is harmless.
        XCTAssertFalse(CoreLoggerInstaller.shared.install())
        XCTAssertFalse(CoreLoggerInstaller.shared.install(minLevel: .error))
    }
}

/// Records what `CoreLoggerInstaller` would hand to the core's `setCoreLogger`.
private final class SetLoggerSpy: @unchecked Sendable {

    struct Call {
        let logger: CoreLogger
        let minLevel: LogLevel
    }

    private let lock = NSLock()
    private var recorded: [Call] = []

    var calls: [Call] {
        lock.withLock { recorded }
    }

    var record: @Sendable (CoreLogger, LogLevel) -> Void {
        { [self] logger, minLevel in
            lock.withLock { recorded.append(Call(logger: logger, minLevel: minLevel)) }
        }
    }
}
