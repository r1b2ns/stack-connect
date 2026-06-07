import Foundation

// Phase 4 · B1b-2 · T-D4 — responsive reflow tiers (design §2.9).
//
// The Home content reflows across three width tiers. Rather than scatter the
// breakpoint arithmetic through the views, the tier is resolved once by a pure,
// GUI-free helper from the width the single `GeometryReader` in
// `WindowsHomeView` reads. That keeps the breakpoint logic unit-testable on the
// macOS host without a window (the actual geometry/resize behaviour is the only
// part that needs VM confirmation), and gives both the provider grid (column
// count) and the toolbar (label length) one shared source of truth.

/// The responsive layout tier for the Home content, per design §2.9.
///
/// - `regular`: window ≥ 860px — 2-column grid, content capped at 860px and
///   centered, full toolbar labels.
/// - `compact`: window 680–859px — 2-column grid filling the width, shortened
///   toolbar labels.
/// - `abbreviated`: window < 680px — single-column grid, abbreviated labels.
enum WindowsLayoutTier: Equatable {
    case regular
    case compact
    case abbreviated

    /// The number of grid columns for this tier (design §2.9): single column
    /// only below the 680px breakpoint, two columns otherwise.
    var gridColumns: Int {
        switch self {
        case .regular, .compact: return 2
        case .abbreviated:       return 1
        }
    }
}

// MARK: - Resolution from available width

/// Resolves the responsive tier from the width available to the Home *content*
/// (i.e. the width the `GeometryReader` inside the padded, 860-capped column
/// reads — NOT the raw window width).
///
/// Design §2.9 states its breakpoints in terms of the window width (≥860 /
/// 680–859 / <680). The `GeometryReader` sits inside the content column, which
/// is inset by `horizontalContentInset` on each side (the VStack's 16px
/// padding) and capped at 860px, so the measured width relates to the window
/// width as `min(window, 860) - 2 * inset`. This helper subtracts the inset
/// back out so the thresholds compare against the effective window width and
/// the design's numbers hold.
///
/// - Parameters:
///   - availableWidth: the width the content `GeometryReader` reports.
///   - horizontalContentInset: the per-side padding between the window edge and
///     the measured content (default 16, matching the Home VStack padding).
/// - Returns: the matching `WindowsLayoutTier`.
func windowsLayoutTier(
    availableWidth: Double,
    horizontalContentInset: Double = 16
) -> WindowsLayoutTier {
    // Reconstruct the effective window width from the measured content width.
    // Below the 860 cap the content tracks the window exactly (minus insets);
    // at/above the cap the content is pinned at (860 - insets), which maps back
    // to >= 860 and correctly resolves to `.regular`.
    let effectiveWindowWidth = availableWidth + 2 * horizontalContentInset

    if effectiveWindowWidth >= 860 {
        return .regular
    } else if effectiveWindowWidth >= 680 {
        return .compact
    } else {
        return .abbreviated
    }
}
