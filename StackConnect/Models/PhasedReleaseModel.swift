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
