import SwiftUI
import UIKit
import StackCore

// Home-screen widget pieces (prototype screen 20). Rows come ready to draw from
// the app's dashboard snapshot; these views only lay them out.

// MARK: - Header

/// Tinted title on the left, "3 apps" (or a trailing view) on the right.
struct WidgetSectionHeader<Trailing: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
            Spacer(minLength: 4)
            trailing
        }
    }
}

extension WidgetSectionHeader where Trailing == Text {
    /// Header with the full list count ("3 apps").
    init(title: String, tint: Color, count: Int) {
        self.title = title
        self.tint = tint
        self.trailing = Text(String(localized: "\(count) apps", comment: "Home-screen widget header: number of apps in the list."))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Empty Row

struct WidgetEmptyRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - App Icon

/// Cached icon bytes from the App Group (WidgetKit can't load remote images at
/// render time), or a gray placeholder.
struct WidgetAppIcon: View {
    var data: Data?
    var size: CGFloat = 28

    private var cornerRadius: CGFloat { size * 0.227 }

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.15))
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(.gray.opacity(0.5))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Platform Glyph

/// The Apple logo (or device symbol) in gray, the Android robot head in green
/// (prototype `.pi`), never the platform name as text.
struct WidgetPlatformGlyph: View {
    let platform: DashboardPlatform

    static let androidGreen = Color(red: 0.10, green: 0.50, blue: 0.22)

    var body: some View {
        Group {
            if let symbol = platform.systemImage {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
            } else {
                Image("AndroidGlyph")
                    .renderingMode(.template)
                    .foregroundStyle(Self.androidGreen)
            }
        }
        .font(.caption2)
        .accessibilityLabel(platform.displayName)
    }
}

// MARK: - Status Line

struct WidgetStatusLine: View {
    let color: Color
    let text: String
    var detail: String?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let detail {
                Text("(\(detail))")
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .font(.caption2)
    }
}

// MARK: - App Row

struct WidgetAppRow: View {
    let row: WidgetDashboardRow
    let iconData: Data?
    var iconSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 10) {
            WidgetAppIcon(data: iconData, size: iconSize)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let platform = row.platform {
                        WidgetPlatformGlyph(platform: platform)
                    }
                }
                WidgetStatusLine(color: row.statusColor.color, text: row.statusText, detail: row.versionText)
                if let progress = row.progress {
                    WidgetProgress(progress: progress)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Progress

/// Phased release (day x of 7) or staged rollout (the percentage is in the
/// status line).
struct WidgetProgress: View {
    let progress: DashboardProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetProgressBar(value: progress.value, color: progress.barColor)
            if case let .phased(day, total, paused) = progress {
                HStack(spacing: 4) {
                    if paused {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    Text(String(localized: "Day \(day) of \(total)"))
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
        }
    }
}

/// A 4 pt rounded bar on a gray track (prototype `.prog`).
struct WidgetProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.2))
                Capsule().fill(color).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityValue(value.formatted(.percent.precision(.fractionLength(0))))
    }
}

// MARK: - Overflow Row

struct WidgetMoreRow: View {
    let remaining: Int

    var body: some View {
        HStack(spacing: 3) {
            Text(String(localized: "+\(remaining) more"))
                .font(.caption2)
                .fontWeight(.semibold)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.blue)
    }
}

// MARK: - Updated

struct WidgetUpdatedFooter: View {
    let date: Date

    var body: some View {
        Text(String(localized: "Updated \(date.formatted(date: .omitted, time: .shortened))",
                    comment: "Home-screen widget footer: when the app last refreshed the data."))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Stars

struct WidgetStars: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < rating ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(rating) out of 5 stars"))
    }
}

// MARK: - Review Row

struct WidgetReviewRow: View {
    let review: WidgetDashboardReview
    let iconData: Data?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            WidgetAppIcon(data: iconData, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(review.appName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let platform = review.platform {
                        WidgetPlatformGlyph(platform: platform)
                    }
                    if review.hasResponse {
                        Image(systemName: "checkmark.bubble.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    Spacer(minLength: 4)
                    WidgetStars(rating: review.rating)
                }

                if let text = review.title.flatMap({ $0.isEmpty ? nil : $0 }) ?? review.body {
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Opens `url` when tapped, or does nothing without one.
struct WidgetRowLink<Content: View>: View {
    let url: String?
    @ViewBuilder var content: Content

    var body: some View {
        // Explicit primary style: a link would otherwise tint its label.
        if let url = url.flatMap(URL.init(string:)) {
            Link(destination: url) { content.foregroundStyle(.primary) }
                .tint(.primary)
        } else {
            content
        }
    }
}
