import Foundation
import SwiftData

@Model
final class PersistedItem {

    // MARK: - Stored Properties

    var typeName: String
    var identifier: String
    var payload: Data
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Init

    init(
        typeName: String,
        identifier: String,
        payload: Data,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.typeName = typeName
        self.identifier = identifier
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
