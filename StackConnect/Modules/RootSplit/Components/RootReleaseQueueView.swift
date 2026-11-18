import SwiftUI

/// Middle column of a release queue: the rows of the matching Home widget.
/// Picking a row opens the app in the detail column.
struct RootReleaseQueueView: View {

    let queue: RootReleaseQueue
    let widget: any HomeWidget
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView {
            widget.makeView()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(queue.title)
        .refreshable { await onRefresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await onRefresh() }
                } label: {
                    Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                }
            }
        }
    }
}
