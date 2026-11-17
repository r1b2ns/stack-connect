import SwiftUI

/// Design System banner for a List row:
/// `{icon} {title / message} ——— [x]` with an optional row of actions below.
///
/// Used by the Home "support the project" card. The close button calls
/// `onDismiss`; when `onTap` is set the whole card is tappable (the close
/// button and the actions keep their own taps). Tracking and state changes
/// belong to the caller.
struct StackBannerCard<Actions: View>: View {

    let systemImage: String
    let tint: Color
    let title: String
    let message: String
    var dismissLabel: String = String(localized: "Dismiss")
    var onTap: (() -> Void)?
    let onDismiss: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        buildContent()
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .modifier(OptionalTapModifier(onTap: onTap))
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func buildContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                buildDismissButton()
            }

            if Actions.self != EmptyView.self {
                HStack(spacing: 16) {
                    actions()
                }
            }
        }
    }

    private func buildDismissButton() -> some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.caption)
                .foregroundStyle(tint.secondary)
                // A comfortable hit area around the small glyph.
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(dismissLabel)
    }
}

/// Makes the whole card tappable only when the caller asked for it, so a
/// banner without `onTap` doesn't swallow taps.
private struct OptionalTapModifier: ViewModifier {
    let onTap: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onTap {
            content.onTapGesture(perform: onTap)
        } else {
            content
        }
    }
}

extension StackBannerCard where Actions == EmptyView {
    /// A banner without an actions row.
    init(
        systemImage: String,
        tint: Color,
        title: String,
        message: String,
        dismissLabel: String = String(localized: "Dismiss"),
        onTap: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.init(
            systemImage: systemImage,
            tint: tint,
            title: title,
            message: message,
            dismissLabel: dismissLabel,
            onTap: onTap,
            onDismiss: onDismiss,
            actions: { EmptyView() }
        )
    }
}

#Preview {
    List {
        StackBannerCard(
            systemImage: "heart.fill",
            tint: .pink,
            title: "Enjoying StackConnect?",
            message: "It's free and open source. If it saves you time, consider leaving a tip.",
            onTap: {},
            onDismiss: {}
        ) {
            Button("Support") {}
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .tint(.pink)
        }

        StackBannerCard(
            systemImage: "exclamationmark.triangle.fill",
            tint: .orange,
            title: "Without actions",
            message: "A banner with only a close button.",
            onDismiss: {}
        )
    }
}
