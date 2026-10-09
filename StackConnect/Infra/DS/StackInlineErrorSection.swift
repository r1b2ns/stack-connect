import SwiftUI

/// List section with an inline warning, shown above content that stays on
/// screen — e.g. a failed sync while the cached data is still displayed.
///
/// A trailing share icon sends the error report through the system share sheet
/// (see `StackErrorShareLink`).
struct StackInlineErrorSection: View {

    let message: String
    /// Where the screen is, for the shared error report.
    let reportContext: ErrorReportContext

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                StackErrorShareLink(message: message, context: reportContext, style: .icon)
                    .font(.footnote)
            }
        }
    }
}
