import SwiftUI

extension View {
    /// Inline navigation title that never truncates: long titles wrap to a
    /// second line and shrink slightly instead of ending in "…" (e.g. the
    /// "Certificates, Identifiers, Devices & Profiles" permission sheet).
    /// The regular `navigationTitle` is kept for VoiceOver and the back menu.
    func stackInlineNavigationTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
