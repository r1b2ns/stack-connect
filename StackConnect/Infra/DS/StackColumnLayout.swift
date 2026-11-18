import CoreGraphics

/// Width rules for screens that switch between a single List and a
/// side-by-side multi-column layout.
///
/// The decision is driven by the width actually available to the view, not by
/// the horizontal size class: an iPad detail column in a three-column split
/// view is `.regular` yet can be under 500pt wide, and a Mac ("Designed for
/// iPad") window can be resized to any width.
enum StackColumnLayout {

    /// Minimum width for two side-by-side Lists (~320pt each), enough for the
    /// row titles and trailing chips to stay on one line. Keeps iPad portrait
    /// with the sidebar hidden (~670pt detail column) in two columns while the
    /// three-column case (~470pt) falls back to the single List.
    static let twoColumnMinimumWidth: CGFloat = 640

    static func fitsTwoColumns(width: CGFloat) -> Bool {
        width >= twoColumnMinimumWidth
    }
}
