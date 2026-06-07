import StackHomeCore
import SwiftUI

// NOTE (T-A6): `HomeRecentReview`, `HomeWidgetDataLoader`, `AppStatusCategorizer`
// and `PhasedReleaseModel` moved into the Foundation-pure `StackHomeCore`
// package. The view-only platform grouping (which depends on the iOS-side
// `AppPlatform` iconography) stays here.

// MARK: - View-only Platform Grouping (iOS)

enum HomeWidgetPlatformGrouping {

    /// Groups apps by their platform in a canonical order, keeping unknown-platform
    /// apps in a trailing `nil` group. Order within each group is preserved.
    static func groupByPlatform(_ apps: [AppModel]) -> [(platform: AppPlatform?, apps: [AppModel])] {
        let order: [AppPlatform] = [.ios, .macOs, .tvOs, .visionOs]
        var groups: [AppPlatform?: [AppModel]] = [:]
        for app in apps {
            let platform = app.platform.flatMap { AppPlatform(rawValue: $0) }
            groups[platform, default: []].append(app)
        }

        var result: [(AppPlatform?, [AppModel])] = []
        for platform in order where !(groups[platform] ?? []).isEmpty {
            result.append((platform, groups[platform] ?? []))
        }
        if let unknown = groups[nil], !unknown.isEmpty {
            result.append((nil, unknown))
        }
        return result
    }
}

// MARK: - Header

struct HomeWidgetSectionHeader: View {
    let icon: String
    let title: String
    let count: Int
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            if count > 0 {
                Text("(\(count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Empty Row

struct HomeWidgetEmptyRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - App Row

struct HomeAppRowView: View {
    let app: AppModel
    var showsPlatform: Bool = false

    private var platform: AppPlatform? {
        app.platform.flatMap { AppPlatform(rawValue: $0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            HomeAppIconView(url: app.iconUrl.flatMap { URL(string: $0) })

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if showsPlatform, let platform {
                        Image(systemName: platform.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let state = app.appStoreState {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(state.color.swiftUIColor)
                            .frame(width: 6, height: 6)

                        Text(state.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let version = app.versionString {
                            Text("(\(version))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct HomeAppIconView: View {
    let url: URL?
    var size: CGFloat = 44

    private var cornerRadius: CGFloat { size * 0.227 }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.15))
            .overlay(
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.gray.opacity(0.4))
            )
    }
}

// MARK: - Phased Progress

struct HomePhasedProgressView: View {
    let day: Int
    let total: Int
    let paused: Bool

    var body: some View {
        let progress = Double(min(day, total)) / Double(total)
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress)
                .tint(paused ? .orange : .blue)
            HStack(spacing: 6) {
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

// MARK: - Review Row

struct HomeReviewRowView: View {
    let item: HomeRecentReview
    var showsApp: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if showsApp {
                        HomeAppIconView(
                            url: item.app.iconUrl.flatMap { URL(string: $0) },
                            size: 24
                        )
                        Text(item.app.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HomeStarsView(rating: item.review.rating)

                    if item.review.hasResponse {
                        HomeReviewAnsweredBadge()
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
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                if let body = item.review.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct HomeReviewAnsweredBadge: View {
    var body: some View {
        Label(String(localized: "Replied"), systemImage: "checkmark.bubble.fill")
            .font(.caption2)
            .foregroundStyle(.green)
            .labelStyle(.iconOnly)
            .accessibilityLabel(String(localized: "Replied"))
    }
}

struct HomeStarsView: View {
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

// MARK: - Color Mapping

extension AppStoreStateColor {
    var swiftUIColor: Color {
        switch self {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
}
