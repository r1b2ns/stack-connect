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
        return LicenseTextFormatter.reflow(text)
    }
}

// MARK: - Formatter

/// Turns a hard-wrapped plain-text license (80-column lines) into text that
/// reflows at any width: single newlines inside a paragraph become spaces,
/// blank lines stay as paragraph breaks. The bundled file is left untouched.
enum LicenseTextFormatter {
    static func reflow(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var paragraphs: [String] = []
        var current: [String] = []

        func flush() {
            if !current.isEmpty {
                paragraphs.append(current.joined(separator: " "))
                current.removeAll()
            }
        }

        for line in normalized.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else {
                current.append(trimmed)
            }
        }
        flush()

        return paragraphs.joined(separator: "\n\n")
    }
}
