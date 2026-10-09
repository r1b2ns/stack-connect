import Foundation
import UIKit

/// Snapshot of the app and device an error report comes from. Contains no user
/// or account data.
struct ErrorReportEnvironment: Equatable, Sendable {

    /// `CFBundleShortVersionString`.
    var appVersion: String
    /// `CFBundleVersion`.
    var buildNumber: String
    /// e.g. "iOS" or "iPadOS".
    var osName: String
    /// e.g. "26.1".
    var osVersion: String
    /// e.g. "iPhone (iPhone18,2)".
    var deviceModel: String
    /// When the report was made.
    var date: Date
    /// Time zone the date is printed in.
    var timeZone: TimeZone

    /// The running app on this device, at `date`.
    @MainActor
    static func current(date: Date = .now, bundle: Bundle = .main) -> ErrorReportEnvironment {
        let info = bundle.infoDictionary
        let device = UIDevice.current
        return ErrorReportEnvironment(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: info?["CFBundleVersion"] as? String ?? "?",
            osName: device.systemName,
            osVersion: device.systemVersion,
            deviceModel: deviceModel(family: device.model),
            date: date,
            timeZone: .current
        )
    }

    // MARK: - Private

    /// The device family with its hardware identifier, e.g. `iPhone (iPhone18,2)`
    /// — the identifier tells the exact model apart. On the simulator the
    /// identifier of the simulated device is used.
    private static func deviceModel(family: String) -> String {
        guard let identifier = hardwareIdentifier(), identifier != family else { return family }
        return "\(family) (\(identifier))"
    }

    private static func hardwareIdentifier() -> String? {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return identifier.isEmpty ? nil : identifier
    }
}
