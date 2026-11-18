import SwiftUI

/// White glyph on a colored rounded square: the icon tile of navigation rows
/// (`StackListRow`), app rows and detail headers. The glyph is an SF Symbol
/// or the Android robot head asset (SF Symbols has no Android glyph).
struct StackIconTile: View {

    let glyph: StackPlatformGlyph
    let color: Color
    var size: CGFloat = 32
    var font: Font = .body

    init(systemName: String, color: Color, size: CGFloat = 32, font: Font = .body) {
        self.init(glyph: .system(systemName), color: color, size: size, font: font)
    }

    init(glyph: StackPlatformGlyph, color: Color, size: CGFloat = 32, font: Font = .body) {
        self.glyph = glyph
        self.color = color
        self.size = size
        self.font = font
    }

    var body: some View {
        buildGlyph()
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225))
    }

    @ViewBuilder
    private func buildGlyph() -> some View {
        switch glyph {
        case .system:
            glyph.image
                .font(font)
        case .android:
            // A template vector asset: sized to the tile instead of the font.
            glyph.image
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.55)
                .accessibilityLabel(glyph.accessibilityName ?? "")
        }
    }
}
