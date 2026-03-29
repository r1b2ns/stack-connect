import SwiftUI
import Charts

struct ChartCardView: View {

    let metric: AnalyticsMetric

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
                .foregroundStyle(metric.color)

            Text(metric.title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer()

            if !metric.dataPoints.isEmpty {
                Text(metric.formattedTotal)
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Chart

    private func buildChart() -> some View {
        Chart(metric.dataPoints) { point in
            AreaMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Value", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [metric.color.opacity(0.3), metric.color.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Value", point.value)
            )
            .foregroundStyle(metric.color)
            .lineStyle(StrokeStyle(lineWidth: 2))
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
        .frame(height: 160)
    }

    // MARK: - States

    private func buildLoadingState() -> some View {
        HStack {
            Spacer()
            ProgressView()
                .frame(height: 120)
            Spacer()
        }
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

    private var axisStride: Int {
        let count = metric.dataPoints.count
        if count <= 7 { return 1 }
        if count <= 30 { return 7 }
        return 15
    }

    private func formatAxisValue(_ value: Double) -> String {
        if metric.isPercentage { return String(format: "%.0f%%", value) }
        if value >= 1_000_000 { return String(format: "%.0fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}
