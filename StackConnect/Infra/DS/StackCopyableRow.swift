import SwiftUI

/// A borderless copy glyph for a List / Form row. The copy itself (and its
/// confirmation toast) belongs to the caller, so it can choose a local-only,
/// expiring clipboard for secrets. Compare `CopyButton`, which writes the
/// general pasteboard on its own.
struct StackCopyIconButton: View {

    /// What VoiceOver announces, e.g. "Copy Host".
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "doc.on.doc")
                .font(.footnote)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .hoverEffect(.highlight)
    }
}

/// `{label} ——— {value} [copy]`: a fact of a detail screen that the user may
/// want to paste somewhere (the network audit's summary rows and headers).
struct StackCopyableRow: View {

    let label: String
    let value: String
    var isMonospaced = false
    /// Stacks the value under the label (long values such as headers).
    var isStacked = false
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: isStacked ? .top : .firstTextBaseline, spacing: 8) {
            if isStacked {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    buildValue()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                buildValue()
                    .multilineTextAlignment(.trailing)
            }
            StackCopyIconButton(
                accessibilityLabel: String(localized: "Copy \(label)", comment: "Accessibility: copy button of a row. Argument: the row's label."),
                action: onCopy
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func buildValue() -> some View {
        Text(value)
            .font(isMonospaced ? .system(.footnote, design: .monospaced) : .body)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    List {
        StackCopyableRow(label: "Duration", value: "412 ms") {}
        StackCopyableRow(label: "Accept", value: "application/json", isMonospaced: true, isStacked: true) {}
    }
}
