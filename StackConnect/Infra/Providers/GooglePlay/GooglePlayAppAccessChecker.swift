import Foundation
import APIProviderPlay

/// Confirms the service account can reach a Play app before it is added to the
/// list manually by package name. Carved out so `GooglePlayAppListViewModel` can
/// be unit-tested without the network.
protocol GooglePlayAppAccessChecking: Sendable {
    func verifyAccess(packageName: String) async throws
}

/// Native `APIProviderPlay` check: opens an androidpublisher edit for the package
/// and deletes it right away. Kept only until the Rust core gains an
/// androidpublisher capability (plan D5); then this moves to the core and
/// `APIProviderPlay` is removed (Phase 3).
struct GooglePlayEditsAccessChecker: GooglePlayAppAccessChecking {

    enum CheckError: LocalizedError {
        case invalidCredentials

        var errorDescription: String? {
            String(localized: "The service account key is invalid. Download a new JSON key from Google Cloud and try again.")
        }
    }

    let credentials: GooglePlayCredentials

    func verifyAccess(packageName: String) async throws {
        let provider = try makeProvider()
        let edit = try await provider.request(
            PlayAPI.v3.applications(packageName).edits.insert()
        )
        if let editId = edit.id {
            try? await provider.request(
                PlayAPI.v3.applications(packageName).edits.delete(editId: editId)
            )
        }
    }

    private func makeProvider() throws -> APIProviderPlay {
        guard let jsonData = credentials.serviceAccountJSON.data(using: .utf8),
              let config = try? PlayConfiguration(serviceAccountJSON: jsonData) else {
            throw CheckError.invalidCredentials
        }
        return APIProviderPlay(configuration: config)
    }
}
