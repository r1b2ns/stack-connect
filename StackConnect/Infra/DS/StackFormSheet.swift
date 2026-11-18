import SwiftUI

extension View {
    /// Sizes a sheet as a centered form on iPad and Mac (prototype #s7), from
    /// iOS 18 (`presentationSizing(.form)`). On iPhone a form sheet still
    /// fills the width, and on iOS 17 the sheet keeps its default size.
    /// Apply it to the sheet's content.
    @ViewBuilder
    func stackFormSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.form)
        } else {
            self
        }
    }
}
