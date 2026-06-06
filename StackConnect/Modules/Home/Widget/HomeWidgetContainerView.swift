import StackHomeCore
import SwiftUI

struct HomeWidgetContainerView: View {

    // Interim: takes the iOS-only view-providing widget (T-A5). Reverts to a
    // `HomeWidgetViewFactory` dispatch in T-A7.
    let widget: any HomeWidgetViewProviding

    var body: some View {
        widget.makeView()
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
