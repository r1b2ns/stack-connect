import SwiftUI

/// One row of a multi-selection list:
/// `[leading] {title / subtitle} ——— {◉ / ○ | note}`.
///
/// Render it as the `label` of a `Button` (usually `StackTrackedButton`); the
/// toggle belongs to the caller. When `note` is set (e.g. "Already added") it
/// replaces the selection indicator: the row is informational and the caller
/// should disable its button. Used by the apps permission picker (export) and
/// the Add Account picker of Google sign-in.
struct StackSelectableRow<Leading: View>: View {

    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    var note: String? = nil
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: 12) {
            leading()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } else {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accent : .secondary)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension StackSelectableRow where Leading == EmptyView {
    /// A row without a leading view.
    init(title: String, subtitle: String? = nil, isSelected: Bool, note: String? = nil) {
        self.init(title: title, subtitle: subtitle, isSelected: isSelected, note: note, leading: { EmptyView() })
    }
}

#Preview {
    List {
        StackSelectableRow(title: "My App", subtitle: "com.example.app", isSelected: true)
        StackSelectableRow(title: "Other App", subtitle: "com.example.other", isSelected: false)
        StackSelectableRow(title: "Added App", subtitle: "com.example.added", isSelected: false, note: "Already added")
        StackSelectableRow(title: "With icon", isSelected: true) {
            StackIconTile(systemName: "play.fill", color: .green)
        }
    }
}
