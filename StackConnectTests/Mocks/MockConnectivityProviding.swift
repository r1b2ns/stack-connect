import Foundation
@testable import StackConnect

/// Deterministic `ConnectivityProviding` for tests. `Sendable` (immutable) so it
/// satisfies the protocol's `Sendable` requirement and can be injected into
/// `AppleAccountConnection`.
struct MockConnectivityProviding: ConnectivityProviding {
    let online: Bool

    init(online: Bool) {
        self.online = online
    }

    func isCurrentlyOnline() -> Bool { online }
}
