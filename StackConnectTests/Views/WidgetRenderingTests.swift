import XCTest
import SwiftUI
import WidgetKit
import StackCore

/// Renders the home-screen widgets (the extension's layouts, compiled into the
/// tests) from the snapshot in the App Group, to compare them with the
/// prototype. Not a snapshot test: nothing is asserted against a baseline.
///
/// Runs only when `TEST_RUNNER_STACK_RENDER_WIDGETS_DIR` names an output folder
/// (xcodebuild passes it to the tests as `STACK_RENDER_WIDGETS_DIR`), e.g.
/// after launching the app with `-StackFakeData YES -StackFakeDataWidgets YES`.
@MainActor
final class WidgetRenderingTests: XCTestCase {

    func testRenderHomeScreenWidgets() throws {
        guard let path = ProcessInfo.processInfo.environment["STACK_RENDER_WIDGETS_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_STACK_RENDER_WIDGETS_DIR to render the widgets.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let snapshot = WidgetDataLoader.load()
        let dashboard = snapshot.dashboard

        // iPhone 17 Pro Max widget sizes (points).
        let medium = CGSize(width: 364, height: 170)
        let large = CGSize(width: 364, height: 382)
        let renders: [(String, WidgetFamily, CGSize, AnyView)] = [
            ("in-review-medium", .systemMedium, medium, AnyView(WidgetAppListView(
                family: .systemMedium, title: "In Review", tint: WidgetTint.inReview, rows: dashboard.inReview,
                totalCount: dashboard.inReviewCount, emptyText: "No apps in review", snapshot: snapshot))),
            ("in-review-large", .systemLarge, large, AnyView(WidgetAppListView(
                family: .systemLarge, title: "In Review", tint: WidgetTint.inReview, rows: dashboard.inReview,
                totalCount: dashboard.inReviewCount, emptyText: "No apps in review", snapshot: snapshot))),
            ("awaiting-release-large", .systemLarge, large, AnyView(WidgetAppListView(
                family: .systemLarge, title: "Awaiting Release", tint: WidgetTint.awaiting, rows: dashboard.awaitingRelease,
                totalCount: dashboard.awaitingReleaseCount, emptyText: "Nothing awaiting release", snapshot: snapshot))),
            ("awaiting-release-medium", .systemMedium, medium, AnyView(WidgetAppListView(
                family: .systemMedium, title: "Awaiting Release", tint: WidgetTint.awaiting, rows: dashboard.awaitingRelease,
                totalCount: dashboard.awaitingReleaseCount, emptyText: "Nothing awaiting release", snapshot: snapshot))),
            ("recent-reviews-medium", .systemMedium, medium, AnyView(RecentReviewsWidgetView(family: .systemMedium, snapshot: snapshot))),
            ("recent-reviews-large", .systemLarge, large, AnyView(RecentReviewsWidgetView(family: .systemLarge, snapshot: snapshot)))
        ]
        for (name, _, size, view) in renders {
            let card = view
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
                .padding(20)
                .background(Color(red: 0.85, green: 0.86, blue: 0.89))
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            let data = try XCTUnwrap(renderer.uiImage?.pngData())
            try data.write(to: output.appendingPathComponent("widget-\(name).png"))
        }
    }
}
