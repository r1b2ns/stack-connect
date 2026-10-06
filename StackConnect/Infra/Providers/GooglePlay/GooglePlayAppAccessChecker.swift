import Foundation

/// Confirms the service account can reach a Play app before it is added to the
/// list manually by package name. Carved out so `GooglePlayAppListViewModel` can
/// be unit-tested without the network.
protocol GooglePlayAppAccessChecking: Sendable {
    func verifyAccess(packageName: String) async throws
}

/// Asks the Rust core for the app's details (`fetchAppDetails`), which doubles
/// as the reachability check:
/// - success: the service account can reach the app;
/// - `StackError.Http(404)`: no such package (an invalid package name is
///   reported the same way, without contacting Google);
/// - `StackError.Auth`: no access to the app, or the Android Publisher API is
///   disabled (the message names the app and the permission).
///
/// Errors are passed through unchanged; callers turn them into copy with
/// `GooglePlayErrorTranslator`.
///
/// Like every app-details read, this opens and deletes a temporary Play edit, so
/// it cancels an edit the same service account has open for the app elsewhere.
/// It only runs on an explicit "Add" by the user.
struct GooglePlayCoreAccessChecker: GooglePlayAppAccessChecking {

    let appDetails: any GooglePlayAppDetailsFetching

    func verifyAccess(packageName: String) async throws {
        _ = try await appDetails.fetchAppDetails(packageName: packageName)
        Log.print.info("[GooglePlay] Access verified for \(packageName)")
    }
}
