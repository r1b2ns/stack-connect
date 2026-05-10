import Foundation

// MARK: - Protocol

@MainActor
protocol LicenseViewModelProtocol: ObservableObject {
    var uiState: LicenseUiState { get set }
}

// MARK: - UiState

struct LicenseUiState {
    var licenseText: String = ""
}

// MARK: - Implementation

@MainActor
final class LicenseViewModel: LicenseViewModelProtocol {

    @Published var uiState = LicenseUiState()

    init() {
        uiState.licenseText = Self.loadLicenseText()
    }

    private static func loadLicenseText() -> String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            Log.print.error("[License] Failed to load LICENSE.txt from bundle")
            return ""
        }
        return text
    }
}
