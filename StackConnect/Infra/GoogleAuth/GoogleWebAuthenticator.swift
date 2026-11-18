import AuthenticationServices
import UIKit

/// Presents Google's authorization page and returns the redirect URL.
@MainActor
protocol GoogleWebAuthenticating: AnyObject {
    /// - Throws: `GoogleAuthError.cancelled` when the user closes the sheet,
    ///   `GoogleAuthError.webSessionFailedToStart` when it can't be shown.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// `ASWebAuthenticationSession` (plan G1: Google blocks embedded web views).
/// Not ephemeral, so the user's existing Google session in Safari is reused.
/// iOS shows its own "wants to use accounts.google.com to sign in" prompt first.
@MainActor
final class GoogleWebAuthenticator: GoogleWebAuthenticating {

    private let contextProvider = GoogleWebPresentationContextProvider()
    /// Retained for the lifetime of the flow (the session is released otherwise).
    private var currentSession: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let handler: @Sendable (URL?, Error?) -> Void = { [weak self] callbackURL, error in
                Task { @MainActor in self?.currentSession = nil }
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleAuthError.cancelled)
                } else {
                    if let error {
                        Log.print.error("[GoogleAuth] Web authentication failed: \(error.localizedDescription, privacy: .public)")
                    }
                    continuation.resume(throwing: GoogleAuthError.webSessionFailedToStart)
                }
            }

            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme), completionHandler: handler)
            } else {
                session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme, completionHandler: handler)
            }
            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session

            if !session.start() {
                currentSession = nil
                continuation.resume(throwing: GoogleAuthError.webSessionFailedToStart)
            }
        }
    }
}

final class GoogleWebPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {

    // Called by AuthenticationServices on the main thread.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
        }
    }
}
