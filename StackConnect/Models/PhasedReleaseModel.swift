import Foundation

struct PhasedReleaseModel: Codable, Identifiable, Hashable {
    let id: String
    var state: PhasedReleaseStatus?
    var startDate: Date?
    var totalPauseDuration: Int?
    var currentDayNumber: Int?

    init(
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

extension PhasedReleaseModel {
    /// The current day to display while a rollout is actively phasing (state
    /// `.active` or `.paused`); nil when it isn't (e.g. `.complete`/`.inactive`
    /// or no day yet), signalling callers to show the plain status instead.
    var displayDayNumber: Int? {
        guard state == .active || state == .paused else { return nil }
        return currentDayNumber
    }

    /// Whether the actively-phasing rollout is paused (drives the dot color).
    var isPausedRollout: Bool { state == .paused }
}

enum PhasedReleaseStatus: String, Codable, CaseIterable, Hashable {
    case inactive = "INACTIVE"
    case active = "ACTIVE"
    case paused = "PAUSED"
    case complete = "COMPLETE"

    var displayName: String {
        switch self {
        case .inactive: return String(localized: "Inactive")
        case .active:   return String(localized: "Active")
        case .paused:   return String(localized: "Paused")
        case .complete: return String(localized: "Complete")
        }
    }
}
