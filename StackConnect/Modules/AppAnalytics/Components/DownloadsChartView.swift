import SwiftUI
import Charts

struct DownloadsChartView: View {

    let metric: AnalyticsMultiSeriesMetric

    private let seriesColors: [String: Color] = [
        "First-time download": .blue,
        "Manual update": .indigo,
        "Redownload": .cyan,
        "Restore": .teal
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            buildHeader()

            if metric.isLoading {
                buildLoadingState()
            } else if let error = metric.error {
                buildErrorState(error)
            } else if metric.dataPoints.isEmpty {
                buildEmptyState()
            } else {
                buildChart()
                buildLegend()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Header

    private func buildHeader() -> some View {
        HStack(spacing: 8) {
            Image(systemName: metric.icon)
                .font(.subheadline)
                .foregroundStyle(.blue)

            Text(metric.title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer()
        }
    }

    // MARK: - Chart

    private func buildChart() -> some View {
        Chart(metric.dataPoints) { point in
            BarMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Count", point.value)
            )
            .foregroundStyle(by: .value("Type", point.series))
        }
        .chartForegroundStyleScale(mapping: { series in
            colorForSeries(series)
        })
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: axisStride)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatAxisValue(v))
                            .font(.caption2)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
            }
        }
        .frame(height: 180)
    }

    // MARK: - Legend

    private func buildLegend() -> some View {
        let series = metric.seriesNames
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(series, id: \.self) { name in
                HStack(spacing: 6) {
                    Circle().fill(colorForSeries(name)).frame(width: 8, height: 8)
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(metric.formattedTotal(for: name))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Spacer()
                }
            }
        }
    }

    // MARK: - States

    private func buildLoadingState() -> some View {
        HStack { Spacer(); ProgressView().frame(height: 120); Spacer() }
    }

    private func buildErrorState(_ error: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
    }

    private func buildEmptyState() -> some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .foregroundStyle(.secondary)
                Text(String(localized: "No data available"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 120)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func colorForSeries(_ series: String) -> Color {
        seriesColors[series] ?? .gray
    }

    private var axisStride: Int {
        let count = Set(metric.dataPoints.map { Calendar.current.startOfDay(for: $0.date) }).count
        if count <= 7 { return 1 }
        if count <= 30 { return 7 }
        return 15
    }

    private func formatAxisValue(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.0fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}
