import SwiftUI

/// The bottom action bar of a detail screen (App Store version detail, Google
/// Play release detail): buttons on the system `.bar` material, disabled with a
/// spinner while an action runs. Attach with `.safeAreaInset(edge: .bottom)`.
struct StackActionBar<Content: View>: View {

    let isBusy: Bool
    let content: Content

    init(isBusy: Bool = false, @ViewBuilder content: () -> Content) {
        self.isBusy = isBusy
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .background(.bar)
        .disabled(isBusy)
        .overlay {
            if isBusy {
                ProgressView()
            }
        }
    }
}

/// Label of an action bar button: icon + title, full width, 12 pt corners.
/// `.filled` is white on `color`; `.outlined` is `color` on a 2 pt border.
struct StackActionButtonLabel: View {

    enum Style {
        case filled
        case outlined
    }

    let title: String
    var icon: String? = nil
    let color: Color
    var style: Style = .filled

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(style == .filled ? Color.white : color)
        .background(style == .filled ? color : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            if style == .outlined {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// A detail row with an icon tile, a title, an optional caption and progress
/// bar, and an optional chevron: `{tile} {title / caption / progress} {›}`.
/// Render it as a `Button`'s label when it navigates.
struct StackSubtitleRow: View {

    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    /// `0...1`; draws a thin progress bar under the caption.
    var progress: Double? = nil
    var progressTint: Color = .teal
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            StackIconTile(systemName: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(progressTint)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
