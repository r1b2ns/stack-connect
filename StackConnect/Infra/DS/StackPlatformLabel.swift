import SwiftUI

extension StackPlatformGlyph {
    /// The glyph of a dashboard platform: the Apple logo / device symbol, or the
    /// green Android robot head.
    init(platform: DashboardPlatform) {
        if let symbol = platform.systemImage {
            self = .system(symbol)
        } else {
            self = .android
        }
    }
}

/// A small platform glyph after a name (prototype `.pi`): Apple platforms in
/// secondary gray, Android in green. VoiceOver reads the platform name.
struct StackPlatformGlyphView: View {
    let platform: DashboardPlatform
    var font: Font = .caption

    var body: some View {
        let glyph = StackPlatformGlyph(platform: platform)
        glyph.image
            .font(font)
            .foregroundStyle(platform == .android ? AnyShapeStyle(Color.androidGlyph) : AnyShapeStyle(.secondary))
            .accessibilityLabel(platform.displayName)
    }
}

/// A platform group header: glyph + platform name ("􀣺 iOS", "Android" in
/// green), as the Home widgets group their rows (prototype screen 19).
struct StackPlatformLabel: View {
    let platform: DashboardPlatform

    var body: some View {
        HStack(spacing: 6) {
            StackPlatformGlyphView(platform: platform, font: .subheadline)
                .accessibilityHidden(true)
            Text(platform.displayName)
        }
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(platform == .android ? AnyShapeStyle(Color.androidGlyph) : AnyShapeStyle(.secondary))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
