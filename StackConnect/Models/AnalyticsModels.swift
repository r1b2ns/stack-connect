import SwiftUI

struct AnalyticsDataPoint: Identifiable, Hashable {
    let id = UUID()
    var date: Date
    var value: Double
}

struct AnalyticsMetric: Identifiable {
    let id: String
    var title: String
    var icon: String
    var color: Color
    var dataPoints: [AnalyticsDataPoint]
    var isLoading: Bool = false
    var isPercentage: Bool = false
    var error: String?

    var total: Double {
        dataPoints.reduce(0) { $0 + $1.value }
    }

    var average: Double {
        guard !dataPoints.isEmpty else { return 0 }
        return total / Double(dataPoints.count)
    }

    var formattedTotal: String {
        if isPercentage {
            return String(format: "%.1f%%", average)
        }
        let value = total
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }
}

struct AnalyticsSeriesDataPoint: Identifiable, Hashable {
    let id = UUID()
    var date: Date
    var value: Double
    var series: String
}

struct AnalyticsMultiSeriesMetric: Identifiable {
    let id: String
    var title: String
    var icon: String
    var dataPoints: [AnalyticsSeriesDataPoint]
    var isLoading: Bool = false
    var error: String?

    var seriesNames: [String] {
        Array(Set(dataPoints.map(\.series))).sorted()
    }

    func total(for series: String) -> Double {
        dataPoints.filter { $0.series == series }.reduce(0) { $0 + $1.value }
    }

    func formattedTotal(for series: String) -> String {
        let value = total(for: series)
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}

enum AnalyticsDateRange: String, CaseIterable, Identifiable {
    case last7Days = "7d"
    case last30Days = "30d"
    case last90Days = "90d"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .last7Days:  return String(localized: "7 Days")
        case .last30Days: return String(localized: "30 Days")
        case .last90Days: return String(localized: "90 Days")
        }
    }

    var days: Int {
        switch self {
        case .last7Days:  return 7
        case .last30Days: return 30
        case .last90Days: return 90
        }
    }

    var startDate: Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}
