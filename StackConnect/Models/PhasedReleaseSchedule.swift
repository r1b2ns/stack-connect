import Foundation

/// Apple's fixed 7-day phased release schedule: the share of users on automatic
/// updates that get the version on each day.
enum PhasedReleaseSchedule {

    /// Percentage of users per day, day 1 first.
    static let percentages = [1, 2, 5, 10, 20, 50, 100]

    static var dayCount: Int { percentages.count }

    /// Users receiving the update on `day` (1-based). Any day outside 1...6
    /// counts as the full rollout.
    static func percentage(forDay day: Int) -> Int {
        guard (1..<dayCount).contains(day) else { return 100 }
        return percentages[day - 1]
    }

    // MARK: - Timeline

    struct Step: Equatable, Identifiable {
        enum Progress: Equatable {
            case done
            case current
            case upcoming
        }

        let day: Int
        let percentage: Int
        let progress: Progress

        var id: Int { day }
    }

    /// The 7 days of a rollout with where it stands: days before the current
    /// one are done, the current day is highlighted (also while paused), and a
    /// complete rollout has every day done. No current day (not started,
    /// inactive) leaves every day upcoming.
    static func steps(for phased: PhasedReleaseModel?) -> [Step] {
        let current: Int?
        switch phased?.state {
        case .complete:
            current = dayCount + 1
        case .active, .paused:
            current = phased?.currentDayNumber.map { min(max($0, 1), dayCount) }
        default:
            current = nil
        }
        return percentages.enumerated().map { index, percentage in
            let day = index + 1
            let progress: Step.Progress
            if let current, day < current {
                progress = .done
            } else if day == current {
                progress = .current
            } else {
                progress = .upcoming
            }
            return Step(day: day, percentage: percentage, progress: progress)
        }
    }
}
