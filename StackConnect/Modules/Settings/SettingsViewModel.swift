import Foundation

// MARK: - Protocol

@MainActor
protocol SettingsViewModelProtocol: ObservableObject {
    var uiState: SettingsUiState { get set }
}

// MARK: - UiState

struct SettingsUiState {
    var appVersion: String = ""
    var buildNumber: String = ""
}

// MARK: - Implementation

@MainActor
final class SettingsViewModel: SettingsViewModelProtocol {

    @Published var uiState = SettingsUiState()

    init() {
        let info = Bundle.main.infoDictionary
        uiState.appVersion = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        uiState.buildNumber = info?["CFBundleVersion"] as? String ?? "1"
    }
}
