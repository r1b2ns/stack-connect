import Foundation
import StackProtocols

enum StackConnectError: LocalizedError {
    case missingImplementation(String)

    var errorDescription: String? {
        switch self {
        case .missingImplementation(let detail):
            return "Missing implementation: \(detail)"
        }
    }
}

final class FirebaseAccountConnection: AccountConnectionProtocol, @unchecked Sendable {

    init() {}

    func validateCredentials() async throws {
        throw StackConnectError.missingImplementation("Firebase credentials validation")
    }

    func fetchApps() async throws -> [AppInfo] {
        throw StackConnectError.missingImplementation("Firebase fetch apps")
    }

    func disconnect() {
        Log.print.info("[Firebase] Disconnected (stub)")
    }
}
