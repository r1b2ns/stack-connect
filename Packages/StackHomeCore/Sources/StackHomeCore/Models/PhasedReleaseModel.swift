import Foundation

/// Phased-release state for an App Store app version.
///
/// Foundation-pure value model shared by the iOS app and the Windows port.
/// Drives the "Awaiting Release" widget's phased grouping (TC-034) and the
/// iOS "Day N of 7" progress row, and is referenced from core by the SDK-free
/// `AppleAccountSyncing` protocol and `AppStoreVersionModel`.
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
        case .inactive: return localizedString("Inactive")
        case .active:   return localizedString("Active")
        case .paused:   return localizedString("Paused")
        case .complete: return localizedString("Complete")
        }
    }
}
