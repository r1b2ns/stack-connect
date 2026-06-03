#if canImport(SwiftData)
import Foundation
import SwiftData

@Model
public final class PersistedItem {

    // MARK: - Stored Properties

    public var typeName: String
    public var identifier: String
    public var payload: Data
    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Init

    public init(
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

#endif
