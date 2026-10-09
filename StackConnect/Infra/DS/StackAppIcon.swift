import SwiftUI

/// An app's store icon loaded from a remote URL and clipped to a rounded square:
/// the one place app rows, pickers and detail headers draw app icons (App Store
/// and Google Play alike).
///
/// - `url == nil` or the download failed → `placeholder`
/// - downloading → `loading` (by default a `ProgressView` the size of the icon)
/// - loaded → the image, scaled to fill
///
/// `cornerRadius` defaults to `StackIconTile`'s ratio (`size * 0.225`), so an
/// icon and a `StackIconTile` placeholder of the same size share one shape.
struct StackAppIcon<Placeholder: View, Loading: View>: View {

    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    private let placeholder: Placeholder
    private let loading: Loading

    init(
        url: URL?,
        size: CGFloat,
        cornerRadius: CGFloat? = nil,
        @ViewBuilder placeholder: () -> Placeholder,
        @ViewBuilder loading: () -> Loading
    ) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius ?? size * 0.225
        self.placeholder = placeholder()
        self.loading = loading()
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        loading
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Defaults

extension StackAppIcon where Loading == StackAppIconLoadingView {

    /// A custom placeholder with the default loading spinner.
    init(
        url: URL?,
        size: CGFloat,
        cornerRadius: CGFloat? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.init(
            url: url,
            size: size,
            cornerRadius: cornerRadius,
            placeholder: placeholder,
            loading: { StackAppIconLoadingView(size: size) }
        )
    }
}

extension StackAppIcon where Placeholder == StackAppIconPlaceholder, Loading == StackAppIconLoadingView {

    /// The generic app placeholder (`StackAppIconPlaceholder`) and the default
    /// loading spinner: the App Store app icon look.
    init(url: URL?, size: CGFloat, cornerRadius: CGFloat? = nil) {
        let radius = cornerRadius ?? size * 0.225
        self.init(url: url, size: size, cornerRadius: radius) {
            StackAppIconPlaceholder(cornerRadius: radius, font: size > 50 ? .title : .title3)
        }
    }
}

// MARK: - Building blocks

/// Default loading state of `StackAppIcon`: a spinner centered in the icon's frame.
struct StackAppIconLoadingView: View {

    let size: CGFloat

    var body: some View {
        ProgressView()
            .frame(width: size, height: size)
    }
}

/// Generic app placeholder: a blue `app.fill` glyph on a light blue rounded square.
struct StackAppIconPlaceholder: View {

    let cornerRadius: CGFloat
    var font: Font = .title3

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.blue.opacity(0.15))
            .overlay {
                Image(systemName: "app.fill")
                    .foregroundStyle(.blue)
                    .font(font)
            }
    }
}
