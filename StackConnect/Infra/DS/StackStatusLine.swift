import SwiftUI

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
    /// SF Symbol drawn last, in tertiary (e.g. `iphone`, `smartphone`).
    var trailingSymbol: String? = nil
    /// VoiceOver name of `trailingSymbol` (e.g. "Android").
    var trailingSymbolLabel: String? = nil
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

                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(trailingSymbolLabel ?? "")
                        .accessibilityHidden(trailingSymbolLabel == nil)
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

    /// Text, detail and glyph as one `Text`, so they wrap together. No-break
    /// spaces keep the detail and the glyph on the last word's line.
    private var flowingText: Text {
        var result = Text(text).foregroundStyle(.secondary)
        if let detail {
            result = result + Text("\u{00A0}(\(detail))").foregroundStyle(.tertiary)
        }
        if let trailingSymbol {
            result = result + Text("\u{00A0}\u{2060}") + Text(Image(systemName: trailingSymbol))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(trailingSymbolLabel ?? "")
        }
        return result
    }
}
