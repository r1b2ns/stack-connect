import SwiftUI

/// White SF Symbol on a colored rounded square: the icon tile of navigation
/// rows (`StackListRow`), app rows and detail headers.
struct StackIconTile: View {

    let systemName: String
    let color: Color
    var size: CGFloat = 32
    var font: Font = .body

    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225))
    }
}
