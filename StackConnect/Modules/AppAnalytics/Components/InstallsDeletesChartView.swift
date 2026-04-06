import SwiftUI
import Charts

struct InstallsDeletesChartView: View {

    let metric: AnalyticsMultiSeriesMetric

    private let installColor: Color = .green
    private let deleteColor: Color = .red

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
            LineMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Count", point.value),
                series: .value("Event", point.series)
            )
            .foregroundStyle(colorForSeries(point.series))
            .lineStyle(StrokeStyle(lineWidth: 2))

            AreaMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Count", point.value),
                series: .value("Event", point.series)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [colorForSeries(point.series).opacity(0.2), colorForSeries(point.series).opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
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
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle().fill(installColor).frame(width: 8, height: 8)
                Text(String(localized: "Installs"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(metric.formattedTotal(for: "Install"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Circle().fill(deleteColor).frame(width: 8, height: 8)
                Text(String(localized: "Deletes"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(metric.formattedTotal(for: "Delete"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            Spacer()
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
        series.lowercased().contains("delete") ? deleteColor : installColor
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
