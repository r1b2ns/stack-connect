import SwiftUI

/// Loading / error / content switch for offline-first screens.
///
/// The spinner and the full-screen error only appear while there is nothing to
/// show; once cached or fresh data exists the content stays on screen (and shows
/// a later sync failure inline, e.g. with `StackInlineErrorSection`).
struct StackLoadableContent<Content: View>: View {

    let isLoading: Bool
    let hasContent: Bool
    let error: String?
    let onRetry: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isLoading && !hasContent {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, !hasContent {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button(String(localized: "Retry"), action: onRetry)
            }
        } else {
            content()
        }
    }
}
