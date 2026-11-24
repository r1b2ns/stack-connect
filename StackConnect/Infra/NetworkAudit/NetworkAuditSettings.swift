import Foundation

/// How long audit events are kept.
enum NetworkAuditRetention: Int, CaseIterable, Sendable, Identifiable {
    case sevenDays = 7
    case fifteenDays = 15
    case thirtyDays = 30

    static let `default`: NetworkAuditRetention = .fifteenDays

    var id: Int { rawValue }
    var days: Int { rawValue }

    /// Events recorded before this instant are purged.
    func cutoff(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now.addingTimeInterval(-Double(days) * 86_400)
    }
}

/// The user's audit preferences. Not sensitive: plain `UserDefaults`.
protocol NetworkAuditSettingsProviding: AnyObject, Sendable {
    var retention: NetworkAuditRetention { get set }
    /// Records request and response bodies (masked). Headers, status and
    /// sizes are always recorded: the audit can't be paused.
    var recordsFullBodies: Bool { get set }
}

final class NetworkAuditSettings: NetworkAuditSettingsProviding, @unchecked Sendable {

    static let shared = NetworkAuditSettings()

    private enum Key {
        static let retention = "networkAudit.retentionDays"
        static let fullBodies = "networkAudit.fullBodies"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var retention: NetworkAuditRetention {
        get { NetworkAuditRetention(rawValue: defaults.integer(forKey: Key.retention)) ?? .default }
        set { defaults.set(newValue.rawValue, forKey: Key.retention) }
    }

    var recordsFullBodies: Bool {
        get { defaults.object(forKey: Key.fullBodies) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.fullBodies) }
    }
}
