import SwiftUI
import UIKit

// MARK: - Section Header

struct WidgetSectionHeader: View {
    let icon: String
    let title: String
    let count: Int
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            if count > 0 {
                Text("(\(count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
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

// MARK: - App Icon Placeholder
//
// Widgets cannot load remote images at render time, so we show a tinted glyph.
// Icon-data preloading can be added later for a richer look.

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

// MARK: - App Row

struct WidgetAppRow: View {
    let app: WidgetApp
    var showsPlatform: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            WidgetAppIcon(data: app.iconData, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(app.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if showsPlatform, let icon = WidgetPlatform.icon(for: app.platform) {
                        Image(systemName: icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let state = app.appStoreState {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(WidgetAppStatus.color(for: state))
                            .frame(width: 5, height: 5)
                        if let name = WidgetAppStatus.displayName(for: state) {
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let version = app.versionString {
                            Text("(\(version))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
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

// MARK: - Phased Progress

struct WidgetPhasedProgress: View {
    let day: Int
    let total: Int
    let paused: Bool

    var body: some View {
        let progress = Double(min(day, total)) / Double(total)
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: progress)
                .tint(paused ? .orange : .blue)
            HStack(spacing: 4) {
                if paused {
                    Image(systemName: "pause.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(String(localized: "Day \(day) of \(total)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Stars

struct WidgetStars: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
    }
}

// MARK: - Review Row

struct WidgetReviewRow: View {
    let item: WidgetReviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                WidgetAppIcon(data: item.app.iconData, size: 18)
                Text(item.app.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                WidgetStars(rating: item.review.rating)

                if item.review.hasResponse {
                    Image(systemName: "checkmark.bubble.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                Spacer(minLength: 0)

                if let date = item.review.createdDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let title = item.review.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            } else if let body = item.review.body, !body.isEmpty {
                Text(body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
