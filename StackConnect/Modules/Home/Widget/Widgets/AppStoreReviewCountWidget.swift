import Combine
import SwiftUI

@MainActor
final class AppStoreReviewCountWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .appStoreReviewCount

    let configuration: HomeWidgetConfiguration

    @Published private(set) var inReviewCount: Int = 0
    @Published private(set) var awaitingReleaseCount: Int = 0
    @Published private(set) var isLoading: Bool = false

    private let storage: PersistentStorable

    init(configuration: HomeWidgetConfiguration, storage: PersistentStorable) {
        self.configuration = configuration
        self.storage = storage
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let active = allApps.filter { !$0.isArchived }
            let phasedByAppId = await loadPhasedReleases(for: active)
            let (inReview, awaiting) = AppStatusCategorizer.categorize(active, phasedByAppId: phasedByAppId)
            inReviewCount = inReview.count
            awaitingReleaseCount = awaiting.count
        } catch {
            Log.print.error("[Widget][AppStoreReviewCount] Failed to load apps: \(error.localizedDescription)")
            inReviewCount = 0
            awaitingReleaseCount = 0
        }
    }

    func makeView() -> AnyView {
        AnyView(AppStoreReviewCountWidgetView(widget: self))
    }

    private func loadPhasedReleases(for apps: [AppModel]) async -> [String: PhasedReleaseModel] {
        var result: [String: PhasedReleaseModel] = [:]
        for app in apps {
            if let phased: PhasedReleaseModel = try? await storage.fetch(PhasedReleaseModel.self, id: "phased.\(app.id)") {
                result[app.id] = phased
            }
        }
        return result
    }
}

// MARK: - View

private struct AppStoreReviewCountWidgetView: View {

    @ObservedObject var widget: AppStoreReviewCountWidget

    private var total: Int { widget.inReviewCount + widget.awaitingReleaseCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            buildHeader()
            buildTotal()
            buildBreakdown()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildHeader() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "app.badge.fill")
                .font(.headline)
                .foregroundStyle(Color.blue)
            Text(String(localized: "App Store Activity"))
                .font(.headline)
                .fontWeight(.semibold)
        }
    }

    private func buildTotal() -> some View {
        Text("\(total)")
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .contentTransition(.numericText())
            .animation(.default, value: total)
            .redacted(reason: widget.isLoading && total == 0 ? .placeholder : [])
    }

    private func buildBreakdown() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            buildBreakdownRow(
                color: .orange,
                label: String(localized: "\(widget.inReviewCount) in review")
            )
            buildBreakdownRow(
                color: .blue,
                label: String(localized: "\(widget.awaitingReleaseCount) awaiting release")
            )
        }
    }

    private func buildBreakdownRow(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
