import Foundation
import LocalAuthentication
import UIKit
import UniformTypeIdentifiers

// MARK: - Owner authentication

/// Confirms the device owner (Face ID / Touch ID, or the passcode) before a
/// secret is revealed or exported.
protocol NetworkAuditOwnerAuthenticating: Sendable {
    func authenticate(reason: String) async -> Bool
}

struct LocalNetworkAuditOwnerAuthenticator: NetworkAuditOwnerAuthenticating {

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        // `.deviceOwnerAuthentication` falls back to the passcode when
        // biometrics are unavailable or fail.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            Log.print.warning("[NetworkAudit] Owner authentication unavailable: \(error?.localizedDescription ?? "", privacy: .public)")
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            Log.print.info("[NetworkAudit] Owner authentication declined")
            return false
        }
    }
}

// MARK: - Pasteboard

/// Copies audit text to the clipboard. Anything that may carry a real secret
/// is copied local-only (never to Universal Clipboard) and expires after
/// `sensitiveExpiration`.
protocol NetworkAuditPasteboardWriting: Sendable {
    func copy(_ text: String, sensitive: Bool)
}

struct SystemNetworkAuditPasteboard: NetworkAuditPasteboardWriting {

    static let sensitiveExpiration: TimeInterval = 120

    func copy(_ text: String, sensitive: Bool) {
        Task { @MainActor in
            if sensitive {
                UIPasteboard.general.setItems(
                    [[UTType.plainText.identifier: text]],
                    options: [
                        .localOnly: true,
                        .expirationDate: Date().addingTimeInterval(Self.sensitiveExpiration)
                    ]
                )
            } else {
                UIPasteboard.general.string = text
            }
        }
    }
}
