import Foundation

/// Bridges a `reimport` deep link into the accounts list, signalling which
/// expired account should be replaced once its import screen appears.
@MainActor
final class ReimportRouter: ObservableObject {
    static let shared = ReimportRouter()

    struct Request: Equatable {
        let accountId: String
        let providerType: ProviderType
    }

    @Published var pending: Request?

    private init() {}

    func request(accountId: String, providerType: ProviderType) {
        pending = Request(accountId: accountId, providerType: providerType)
    }
}
