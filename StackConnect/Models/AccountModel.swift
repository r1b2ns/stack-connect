import Foundation

struct AccountModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let providerType: ProviderType
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        providerType: ProviderType,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.createdAt = createdAt
    }
}
