import SwiftUI

/// List section with an inline warning, shown above content that stays on
/// screen — e.g. a failed sync while the cached data is still displayed.
struct StackInlineErrorSection: View {

    let message: String

    var body: some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
