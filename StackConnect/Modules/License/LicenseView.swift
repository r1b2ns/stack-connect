import SwiftUI

// MARK: - Factory

@MainActor
struct LicenseViewFactory {
    static func build() -> some View {
        LicenseEntry()
    }
}

// MARK: - Entry

private struct LicenseEntry: View {
    @StateObject private var viewModel = LicenseViewModel()

    var body: some View {
        LicenseView(viewModel: viewModel)
    }
}

// MARK: - View

struct LicenseView<ViewModel: LicenseViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        ScrollView {
            Text(viewModel.uiState.licenseText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle(String(localized: "License"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
