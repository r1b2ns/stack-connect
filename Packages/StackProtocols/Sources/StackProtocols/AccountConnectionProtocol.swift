import Foundation

public protocol AccountConnectionProtocol: Sendable {
    func validateCredentials() async throws
    func fetchApps() async throws -> [AppInfo]
    func disconnect()
}
