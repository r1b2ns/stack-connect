import Foundation

/// Foundation-pure value model for an App Store phased release. Migrated into
/// StackHomeCore so the SDK-free `AppleAccountSyncing` protocol can reference it
/// from core.
public struct PhasedReleaseModel: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var state: PhasedReleaseStatus?
    public var startDate: Date?
    public var totalPauseDuration: Int?
    public var currentDayNumber: Int?

    public init(
        id: String,
        state: PhasedReleaseStatus? = nil,
        startDate: Date? = nil,
        totalPauseDuration: Int? = nil,
        currentDayNumber: Int? = nil
    ) {
        self.id = id
        self.state = state
        self.startDate = startDate
        self.totalPauseDuration = totalPauseDuration
        self.currentDayNumber = currentDayNumber
    }
}

public enum PhasedReleaseStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case inactive = "INACTIVE"
    case active = "ACTIVE"
    case paused = "PAUSED"
    case complete = "COMPLETE"

    public var displayName: String {
        switch self {
        case .inactive: return String(localized: "Inactive")
        case .active:   return String(localized: "Active")
        case .paused:   return String(localized: "Paused")
        case .complete: return String(localized: "Complete")
        }
    }
}
