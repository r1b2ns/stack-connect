import SwiftUI
import UIKit

// MARK: - Palette

/// The prototype's light tints, with dark-mode counterparts.
enum NetworkAuditPalette {

    static func color(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    static let blueFill = color(light: hex(0xE5F0FF), dark: hex(0x0A84FF, alpha: 0.22))
    static let blueText = color(light: hex(0x004A9E), dark: hex(0x64B5FF))
    static let orangeFill = color(light: hex(0xFFEBD9), dark: hex(0xFF9F0A, alpha: 0.22))
    static let orangeText = color(light: hex(0x8A3B00), dark: hex(0xFFB35C))
    static let purpleFill = color(light: hex(0xEFE6FF), dark: hex(0xBF5AF2, alpha: 0.22))
    static let purpleText = color(light: hex(0x4B2A9B), dark: hex(0xD7A6FF))
    static let greenFill = color(light: hex(0xE6F5EA), dark: hex(0x30D158, alpha: 0.22))
    static let greenText = color(light: hex(0x1B6B32), dark: hex(0x6EE08E))
    static let redFill = color(light: hex(0xFFE5E8), dark: hex(0xFF453A, alpha: 0.22))
    static let redText = color(light: hex(0xB3001A), dark: hex(0xFF7A70))
    static let grayFill = Color(.systemGray5)
    static let grayText = Color.secondary
    /// The on-device banner's tile.
    static let indigo = Color(hex(0x3634A3))
    /// "Delete" buttons.
    static let destructive = color(light: hex(0xD70015), dark: hex(0xFF453A))
}

// MARK: - Category style

extension NetworkAuditCategory {

    var title: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .telemetry: return String(localized: "Telemetry", comment: "Network audit filter chip: analytics, crash reports and remote configuration.")
        case .local: return String(localized: "On Device", comment: "Network audit filter chip: events that never left the device.")
        case .other: return String(localized: "Other", comment: "Network audit: category of a host outside Apple, Google and telemetry.")
        }
    }

    var fill: Color {
        switch self {
        case .apple: return NetworkAuditPalette.blueFill
        case .google: return NetworkAuditPalette.orangeFill
        case .telemetry: return NetworkAuditPalette.purpleFill
        case .local: return NetworkAuditPalette.greenFill
        case .other: return NetworkAuditPalette.grayFill
        }
    }

    var foreground: Color {
        switch self {
        case .apple: return NetworkAuditPalette.blueText
        case .google: return NetworkAuditPalette.orangeText
        case .telemetry: return NetworkAuditPalette.purpleText
        case .local: return NetworkAuditPalette.greenText
        case .other: return NetworkAuditPalette.grayText
        }
    }
}

// MARK: - Badges

/// A small rounded tag: category ("Apple"), "SECRET".
struct NetworkAuditTag: View {
    let title: String
    let fill: Color
    let foreground: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

extension NetworkAuditTag {
    init(category: NetworkAuditCategory) {
        self.init(title: category.title, fill: category.fill, foreground: category.foreground)
    }

    static var secret: NetworkAuditTag {
        NetworkAuditTag(
            title: String(localized: "SECRET", comment: "Network audit detail: badge of a secret header."),
            fill: NetworkAuditPalette.orangeFill,
            foreground: NetworkAuditPalette.orangeText
        )
    }
}

/// The method / status pills of the detail header.
struct NetworkAuditPill: View {
    let title: String
    var isMonospaced = false
    let fill: Color
    let foreground: Color

    var body: some View {
        Text(title)
            .font(isMonospaced ? .system(size: 13, weight: .bold, design: .monospaced) : .system(size: 13, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    static func method(_ method: String) -> NetworkAuditPill {
        NetworkAuditPill(title: method, isMonospaced: true, fill: NetworkAuditPalette.blueFill, foreground: NetworkAuditPalette.blueText)
    }

    static func status(_ title: String, isSuccess: Bool) -> NetworkAuditPill {
        NetworkAuditPill(
            title: title,
            fill: isSuccess ? NetworkAuditPalette.greenFill : NetworkAuditPalette.redFill,
            foreground: isSuccess ? NetworkAuditPalette.greenText : NetworkAuditPalette.redText
        )
    }
}

// MARK: - Event row

/// One event of the Audit list: direction badge, method, host, time; path
/// on one line; category, status and sizes.
struct NetworkAuditEventRow: View {

    let summary: NetworkAuditEventSummary
    /// The iPad list: no direction badge, smaller type.
    var isCompact = false
    var isSelected = false

    var body: some View {
        HStack(alignment: .top, spacing: isCompact ? 10 : 12) {
            if !isCompact {
                buildDirectionBadge()
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(summary.method)
                        .font(.system(size: isCompact ? 11 : 12, weight: .bold, design: .monospaced))
                    Text(summary.host)
                        .font(.system(size: isCompact ? 14 : 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(summary.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: isCompact ? 12 : 13))
                        .foregroundStyle(secondaryStyle)
                        .monospacedDigit()
                }
                Text(summary.path)
                    .font(.system(size: isCompact ? 12 : 13, design: .monospaced))
                    .foregroundStyle(secondaryStyle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isCompact {
                    Text(verbatim: "\(NetworkAuditStatus.title(for: summary)) · \(summary.category.title)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(statusColor))
                } else {
                    HStack(spacing: 8) {
                        NetworkAuditTag(category: summary.category)
                        Text(NetworkAuditStatus.title(for: summary))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(statusColor)
                        Text(sizes)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .accessibilityElement(children: .combine)
    }

    private var secondaryStyle: AnyShapeStyle {
        isSelected ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(Color.secondary)
    }

    private var statusColor: Color {
        summary.isSuccess ? NetworkAuditPalette.greenText : NetworkAuditPalette.redText
    }

    private var sizes: String {
        if summary.kind != .http {
            return summary.direction == .inbound
                ? NetworkAuditFormatting.bytes(summary.bytesReceived)
                : NetworkAuditFormatting.bytes(summary.bytesSent)
        }
        return "↑ \(NetworkAuditFormatting.bytes(summary.bytesSent)) · ↓ \(NetworkAuditFormatting.bytes(summary.bytesReceived))"
    }

    private func buildDirectionBadge() -> some View {
        let isOutbound = summary.direction == .outbound
        return Image(systemName: isOutbound ? "arrow.up.right" : "arrow.down.left")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isOutbound ? Color.accentColor : NetworkAuditPalette.greenText)
            .frame(width: 28, height: 28)
            .background(isOutbound ? NetworkAuditPalette.blueFill : NetworkAuditPalette.greenFill, in: Circle())
            .accessibilityLabel(isOutbound
                ? String(localized: "Sent", comment: "Network audit: an outbound event.")
                : String(localized: "Received", comment: "Network audit: an inbound event."))
    }
}

// MARK: - Destination row

/// One host of the Destinations segment: host + count + copy, purpose,
/// owner badge + sizes.
struct NetworkAuditDestinationRow: View {

    let destination: NetworkAuditDestination
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(destination.host)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(localized: "\(destination.requestCount) req.", comment: "Network audit: request count of a destination."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                StackCopyIconButton(
                    accessibilityLabel: String(localized: "Copy \(destination.host)", comment: "Accessibility: copy button of a row. Argument: the row's label."),
                    action: onCopy
                )
                .padding(.trailing, -8)
            }
            Text(destination.purpose)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                NetworkAuditTag(category: destination.category)
                Text(verbatim: "↑ \(NetworkAuditFormatting.bytes(destination.bytesSent)) · ↓ \(NetworkAuditFormatting.bytes(destination.bytesReceived))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}
