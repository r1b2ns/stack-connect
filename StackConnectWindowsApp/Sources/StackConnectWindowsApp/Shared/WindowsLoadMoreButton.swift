import SwiftCrossUI

// T-W04 — A "Load More" button with a loading state for pagination (design
// spec section A-05: explicit Load More, no infinite scroll).
//
// When `isLoading` is `false` the button shows "Load More" and is tappable.
// When `isLoading` is `true` the button is replaced by a `ProgressView`
// spinner, indicating data is being fetched. The caller drives the
// `isLoading` state from the pagination model.

struct WindowsLoadMoreButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView()
            } else {
                Button("Load More", action: action)
            }
            Spacer()
        }
        .padding(8)
    }
}
