import SwiftUI

/// A small platform glyph drawn after a status or a title: an SF Symbol in
/// tertiary, or the green Android robot head of the prototypes (`.pi.and`,
/// asset `AndroidGlyph`). SF Symbols has no Android glyph, and the generic
/// `smartphone` symbol reads as a missing-character box at caption size.
enum StackPlatformGlyph: Hashable {
    case system(String)
    case android

    var image: Image {
        switch self {
        case .system(let name): return Image(systemName: name)
        case .android:          return Image("AndroidGlyph")
        }
    }

    var style: AnyShapeStyle {
        switch self {
        case .system:  return AnyShapeStyle(.tertiary)
        case .android: return AnyShapeStyle(Color.androidGlyph)
        }
    }

    /// VoiceOver name.
    var accessibilityName: String? {
        switch self {
        case .system:  return nil
        case .android: return String(localized: "Android")
        }
    }
}

extension Color {
    /// The prototypes' Android green (`#1A7F37`, lighter in dark mode).
    static let androidGlyph = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.27, green: 0.75, blue: 0.40, alpha: 1)
            : UIColor(red: 0.10, green: 0.50, blue: 0.22, alpha: 1)
    })
}

/// One status line under a list row title: `● {text} ({detail}) {glyph}` — a
/// 6 pt colored dot, the status in secondary caption text, an optional
/// tertiary detail in parentheses (usually a version) and an optional trailing
/// platform glyph.
///
/// Shared by the App Store app list (one line per platform), the Google Play
/// app list (one line per track) and the Google Play app detail release rows.
struct StackStatusLine: View {

    let color: Color
    let text: String
    var detail: String? = nil
    /// Platform glyph drawn last (e.g. `.android`).
    var trailingGlyph: StackPlatformGlyph? = nil
    /// Long statuses wrap onto a second line (detail and glyph flow with the
    /// text) instead of truncating. Off by default: one line, truncated.
    var wraps: Bool = false

    var body: some View {
        if wraps {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                dot
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
                flowingText
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 4) {
                dot

                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let detail {
                    Text("(\(detail))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let trailingGlyph {
                    trailingGlyph.image
                        .font(.caption2)
                        .foregroundStyle(trailingGlyph.style)
                        .accessibilityLabel(trailingGlyph.accessibilityName ?? "")
                        .accessibilityHidden(trailingGlyph.accessibilityName == nil)
                }
            }
        }
    }

    private var dot: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }

    /// Text, detail and glyph as one `Text`, so they wrap together. A no-break
    /// space keeps the detail and the glyph on the last word's line.
    private var flowingText: Text {
        var result = Text(text).foregroundStyle(.secondary)
        if let detail {
            result = result + Text("\u{00A0}(\(detail))").foregroundStyle(.tertiary)
        }
        if let trailingGlyph {
            result = result + Text("\u{00A0}") + Text(trailingGlyph.image)
                .font(.caption2)
                .foregroundStyle(trailingGlyph.style)
                .accessibilityLabel(trailingGlyph.accessibilityName ?? "")
        }
        return result
    }
}
