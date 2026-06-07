import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-B5 — the reusable Home grid card + the manual 2-column
// grid that lays out the provider cards and the Settings cell (design §2.4 step
// 3, §2.8, §2.9). US-001 (provider cards grid) + US-002 (Settings card).
//
// SwiftCrossUI 0.7 has no `LazyVGrid`, so the grid is built by hand from
// HStack/VStack pairs (refinement A-1). The cell ordering — the two provider
// cards followed by the Settings cell as the 3rd cell — is pulled into a pure,
// GUI-free helper (`HomeGridCell` / `homeGridCells`) so it is unit-testable on
// the macOS host without a window (TC-006/008 logic).

// MARK: - Pure cell model (GUI-free, unit-testable)

/// A single cell of the Home grid. The grid is the provider cards (from the
/// shared core state) followed by a trailing Settings cell.
///
/// Foundation/SwiftCrossUI-agnostic on purpose: it carries only the data needed
/// to render and route, so the ordering logic can be asserted in a plain unit
/// test (no GUI, no window).
enum HomeGridCell: Equatable {
    case provider(ProviderType)
    case settings
}

/// Builds the ordered list of Home grid cells: every provider card in order,
/// then the Settings cell as the final (3rd) cell. The providers come straight
/// from `model.state.providers`, which the core already filters down to the two
/// supported providers (Apple + Firebase — never Google Play), so this helper
/// does not re-filter; it only fixes the provider-then-Settings ordering.
///
/// - Parameter providers: the providers to render, in display order.
/// - Returns: `[.provider(p0), .provider(p1), …, .settings]`.
func homeGridCells(providers: [ProviderType]) -> [HomeGridCell] {
    providers.map(HomeGridCell.provider) + [.settings]
}

// MARK: - Reusable card view

/// A single radius-8 tinted Home card: a glyph/text icon substitute on the left,
/// a bold display name, and a ">" disclosure on the right. The whole card is
/// tappable. Used for both the provider cards and the Settings cell so they share
/// the exact same height, radius, and styling (US-002 AC-3).
struct WindowsProviderCardView: View {
    /// The icon substitute (text/glyph) shown on the leading edge (design §2.8).
    let glyph: String
    /// The color the glyph is tinted with (provider color, or gray for Settings).
    let glyphColor: Color
    /// The user-facing title (provider `displayName` or "Settings").
    let title: String
    /// The card's tint. The background is this at ~8% opacity and the 1px border
    /// is this at a stronger opacity, so the two providers are visually distinct
    /// (US-001 AC-4). Settings uses a neutral gray tint (US-002 AC-3).
    let tint: Color
    /// The push action invoked on tap (provider → `.accountsList`, Settings →
    /// `.settings`).
    let action: () -> Void

    /// Fixed card height (design §2.4 step 3: ~120px tall).
    private let cardHeight = 120.0
    /// Fixed corner radius (design §2.4 step 3: radius 8).
    private let cardRadius = 8

    var body: some View {
        HStack(spacing: 12) {
            Text(glyph)
                .fontWeight(.bold)
                .foregroundColor(glyphColor)
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(">")
                .foregroundColor(.gray)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight)
        .background(tint.opacity(0.08))
        .cornerRadius(cardRadius)
        .overlay {
            // 1px tinted border distinguishing the cards (design §2.4 step 3).
            RoundedRectangle(cornerRadius: Double(cardRadius))
                .stroke(tint.opacity(0.4), style: StrokeStyle(width: 1.0))
        }
        .onTapGesture(perform: action)
    }
}

// MARK: - Cell → card mapping (icon/color substitution, design §2.8)

extension HomeGridCell {
    /// The text/glyph icon substitute for this cell (design §2.8). Apple has no
    /// usable Unicode mark, so it renders as bold "ASC"; Firebase as 🔥; Settings
    /// as the gear ⚙.
    var glyph: String {
        switch self {
        case .provider(let provider):
            switch provider {
            case .apple:      return "ASC"
            case .firebase:   return "🔥"
            case .googlePlay: return "▶"
            }
        case .settings:
            return "⚙"
        }
    }

    /// The user-facing title: the provider's localized `displayName`, or
    /// "Settings" for the Settings cell.
    var title: String {
        switch self {
        case .provider(let provider): return provider.displayName
        case .settings:               return "Settings"
        }
    }

    /// The card tint. Providers map their raw `colorName` token to a SwiftCrossUI
    /// color (Apple → blue, Firebase → orange) so the two are distinct; Settings
    /// uses a neutral gray for the "light gray" styling (US-002 AC-3).
    var tint: Color {
        switch self {
        case .provider(let provider): return Self.color(named: provider.colorName)
        case .settings:               return .gray
        }
    }

    /// Maps a raw color-name token (from `ProviderType.colorName`) to a
    /// SwiftCrossUI `Color`. The shared core is Foundation-pure and only exposes
    /// string tokens, so the Windows port resolves them to its own palette here.
    static func color(named name: String) -> Color {
        switch name {
        case "blue":   return .blue
        case "orange": return .orange
        case "green":  return .green
        case "yellow": return .yellow
        case "red":    return .red
        case "purple": return .purple
        case "gray":   return .gray
        default:       return .gray
        }
    }
}
