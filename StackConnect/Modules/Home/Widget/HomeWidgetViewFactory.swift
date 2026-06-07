import StackHomeCore
import SwiftUI

/// iOS-only SwiftUI factory that maps a widget's `HomeWidgetKind` + its concrete
/// observable adapter onto the matching Home widget subview.
///
/// **Why this exists (T-A7):** T-A5 removed `makeView()` from the shared
/// `StackHomeCore.HomeWidget` protocol (US-010 AC-5) — view-building is now
/// platform-specific. The interim `HomeWidgetViewProviding`/`makeView()` bridge
/// that T-A5/T-A6 left in the app target has been deleted; this factory replaces
/// it. The Windows port renders its own SwiftCrossUI views from the same widget
/// result data.
///
/// **Exhaustive dispatch (no `default`):** the `switch` covers every
/// `HomeWidgetKind` with no `default` case. Adding a new kind to the enum
/// therefore becomes a *compile error* here, instead of silently dropping the
/// widget at runtime — which is exactly the failure mode Staff Review flagged on
/// the old `as? any HomeWidgetViewProviding` cast in `HomeView.swift`.
@MainActor
enum HomeWidgetViewFactory {

    /// Builds the SwiftUI subview for a widget, dispatching on its `kind`.
    ///
    /// Each case downcasts the `any HomeWidget` to the concrete iOS adapter so
    /// the returned view can observe it (`@ObservedObject`) and update live as
    /// `load()` republishes `data`/`isLoading`. A failed downcast (kind/adapter
    /// mismatch — not expected, the registry pairs them) renders nothing.
    @ViewBuilder
    static func build(for widget: any HomeWidget) -> some View {
        switch widget.kind {
        case .inReview:
            if let widget = widget as? InReviewWidget {
                InReviewWidgetView(widget: widget)
            }
        case .awaitingRelease:
            if let widget = widget as? AwaitingReleaseWidget {
                AwaitingReleaseWidgetView(widget: widget)
            }
        case .recentReviews:
            if let widget = widget as? RecentReviewsWidget {
                RecentReviewsWidgetView(widget: widget)
            }
        }
    }
}

// MARK: - In Review

private struct InReviewWidgetView: View {

    @ObservedObject var widget: InReviewWidget
    @EnvironmentObject private var coordinator: HomeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeWidgetSectionHeader(
                icon: "magnifyingglass.circle.fill",
                title: String(localized: "In Review"),
                count: widget.data.apps.count,
                tint: .orange
            )

            if widget.data.apps.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "checkmark.circle",
                    text: String(localized: "No apps in review")
                )
            } else {
                let groups = HomeWidgetPlatformGrouping.groupByPlatform(widget.data.apps)
                let showsHeaders = groups.count > 1
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if showsHeaders, let platform = group.platform {
                        HStack(spacing: 6) {
                            Image(systemName: platform.icon)
                            Text(platform.displayName)
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }

                    ForEach(group.apps) { app in
                        Button {
                            coordinator.navigateToAppDetail(
                                app,
                                account: HomeWidgetDataLoader.account(for: app, in: widget.data.accountsMap)
                            )
                        } label: {
                            HomeAppRowView(app: app, showsPlatform: true)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Awaiting Release

private struct AwaitingReleaseWidgetView: View {

    @ObservedObject var widget: AwaitingReleaseWidget
    @EnvironmentObject private var coordinator: HomeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeWidgetSectionHeader(
                icon: "paperplane.circle.fill",
                title: String(localized: "Awaiting Release"),
                count: widget.data.apps.count,
                tint: .blue
            )

            if widget.data.apps.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "checkmark.circle",
                    text: String(localized: "Nothing awaiting release")
                )
            } else {
                ForEach(widget.data.apps) { app in
                    Button {
                        coordinator.navigateToAppDetail(
                            app,
                            account: HomeWidgetDataLoader.account(for: app, in: widget.data.accountsMap)
                        )
                    } label: {
                        buildRow(app)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildRow(_ app: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeAppRowView(app: app)
            if let phased = widget.data.phasedByAppId[app.id],
               phased.state == .active || phased.state == .paused,
               let day = phased.currentDayNumber {
                HomePhasedProgressView(day: day, total: 7, paused: phased.state == .paused)
                    .padding(.leading, 56)
            }
        }
    }
}

// MARK: - Recent Reviews

private struct RecentReviewsWidgetView: View {

    @ObservedObject var widget: RecentReviewsWidget
    @EnvironmentObject private var coordinator: HomeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeWidgetSectionHeader(
                icon: "star.bubble.fill",
                title: String(localized: "Recent Reviews"),
                count: widget.data.reviews.count,
                tint: .yellow
            )

            if widget.data.reviews.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "clock.arrow.circlepath",
                    text: String(localized: "Reviews will appear after the next sync")
                )
            } else {
                ForEach(Array(widget.data.reviews.enumerated()), id: \.element.id) { index, item in
                    Button {
                        coordinator.navigateToReviewDetail(
                            review: item.review,
                            appName: item.app.name,
                            account: HomeWidgetDataLoader.account(for: item.app, in: widget.data.accountsMap)
                        )
                    } label: {
                        HomeReviewRowView(item: item)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)

                    if index < widget.data.reviews.count - 1 {
                        Divider()
                    }
                }

                Button {
                    coordinator.navigateToAllReviews()
                } label: {
                    HStack(spacing: 4) {
                        Text(String(localized: "See more"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
