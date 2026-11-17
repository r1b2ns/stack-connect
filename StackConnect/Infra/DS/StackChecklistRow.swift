import SwiftUI

/// One row of a pre-publish checklist: `{✓ / ⚠︎} {title / detail} {value}`.
/// Shared by the App Store pre-submit checklist and the Google Play review
/// checklist. `isSatisfied == nil` draws no indicator (an informational row) but keeps
/// its space, so titles stay aligned.
struct StackChecklistRow: View {

    let title: String
    var detail: String? = nil
    var value: String? = nil
    var isSatisfied: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let isSatisfied {
                Image(systemName: isSatisfied ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isSatisfied ? .green : .orange)
                    .frame(width: 24)
                    .accessibilityLabel(isSatisfied ? Text("Done") : Text("Needs attention"))
            } else {
                // Keeps titles aligned with the rows that have an indicator.
                Image(systemName: "checkmark.circle.fill")
                    .frame(width: 24)
                    .hidden()
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(isSatisfied == false ? .orange : .secondary)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
