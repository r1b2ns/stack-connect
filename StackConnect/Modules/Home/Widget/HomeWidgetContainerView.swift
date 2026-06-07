import StackHomeCore
import SwiftUI

/// Chrome around a single Home widget: padding, gray card background, rounded
/// border. The widget's content view is produced by `HomeWidgetViewFactory`
/// (T-A7), which dispatches on `HomeWidgetKind` — replacing the interim
/// `HomeWidgetViewProviding.makeView()` bridge.
struct HomeWidgetContainerView: View {

    let widget: any HomeWidget

    var body: some View {
        HomeWidgetViewFactory.build(for: widget)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
    }
}
