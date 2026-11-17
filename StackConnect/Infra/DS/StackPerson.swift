import SwiftUI

/// Round tinted avatar with initials (or a symbol when there are none): the
/// leading element of user rows and user detail headers, App Store Connect and
/// Google Play alike.
struct StackAvatar: View {

    let initials: String
    let tint: Color
    var size: CGFloat = 36
    /// Shown instead of empty initials.
    var placeholderSymbol = "person.fill"

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.15))

            if initials.isEmpty {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(tint)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A user row: `{avatar} {title / subtitle / detail} ——— [badge] {chevron}`.
/// Render it as the label of a button; the tap belongs to the caller.
struct StackPersonRow: View {

    struct Badge {
        let title: String
        let color: Color
    }

    let avatar: StackAvatar
    let title: String
    var subtitle: String?
    var detail: String?
    var badge: Badge?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            if let badge {
                StackCapsuleBadge(title: badge.title, color: badge.color)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The header of a user detail: large avatar, name, e-mail and a state badge.
struct StackPersonHeader: View {

    let avatar: StackAvatar
    let title: String
    var subtitle: String?
    var badge: StackPersonRow.Badge?

    var body: some View {
        HStack(spacing: 16) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                // An address (pending invitation) must not break mid-word.
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.middle)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let badge {
                    StackCapsuleBadge(title: badge.title, color: badge.color)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
