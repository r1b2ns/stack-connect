import Foundation
import SwiftData

@ModelActor
public final actor SwiftDataStorable: PersistentStorable {

    // MARK: - Helpers

    private func typeName<T>(for type: T.Type) -> String {
        String(describing: type)
    }

    private func descriptor(
        typeName name: String,
        identifier: String? = nil
    ) -> FetchDescriptor<PersistedItem> {
        if let identifier {
            let predicate = #Predicate<PersistedItem> {
                $0.typeName == name && $0.identifier == identifier
            }
            return FetchDescriptor(predicate: predicate)
        } else {
            let predicate = #Predicate<PersistedItem> {
                $0.typeName == name
            }
            return FetchDescriptor(predicate: predicate)
        }
    }

    // MARK: - Create / Update

    public func save<T: Codable>(_ item: T, id: String) throws {
        let name = typeName(for: T.self)

        guard let payload = try? JSONEncoder().encode(item) else {
            throw PersistentStorableError.encodingFailed
        }

        let fetchDescriptor = descriptor(typeName: name, identifier: id)

        if let existing = try modelContext.fetch(fetchDescriptor).first {
            existing.payload = payload
            existing.updatedAt = .now
        } else {
            let newItem = PersistedItem(
                typeName: name,
                identifier: id,
                payload: payload
            )
            modelContext.insert(newItem)
        }

        try modelContext.save()
    }

    // MARK: - Read

    public func fetch<T: Codable>(_ type: T.Type, id: String) throws -> T? {
        try fetch(type, id: id, typeName: typeName(for: type))
    }

    public func fetch<T: Codable>(_ type: T.Type, id: String, typeName name: String) throws -> T? {
        let fetchDescriptor = descriptor(typeName: name, identifier: id)

        guard let item = try modelContext.fetch(fetchDescriptor).first else {
            return nil
        }

        guard let decoded = try? JSONDecoder().decode(T.self, from: item.payload) else {
            throw PersistentStorableError.decodingFailed
        }

        return decoded
    }

    public func fetchAll<T: Codable>(_ type: T.Type) throws -> [T] {
        try fetchAll(type, typeName: typeName(for: type))
    }

    public func fetchAll<T: Codable>(_ type: T.Type, typeName name: String) throws -> [T] {
        let fetchDescriptor = descriptor(typeName: name)

        let items = try modelContext.fetch(fetchDescriptor)

        return items.compactMap { item in
            do {
                return try JSONDecoder().decode(T.self, from: item.payload)
            } catch {
                Log.print.warning("Failed to decode PersistedItem (\(item.identifier)): \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - Delete

    public func delete<T: Codable>(_ type: T.Type, id: String) throws {
        let name = typeName(for: type)
        let fetchDescriptor = descriptor(typeName: name, identifier: id)

        if let item = try modelContext.fetch(fetchDescriptor).first {
            modelContext.delete(item)
            try modelContext.save()
        }
    }

    public func deleteAll<T: Codable>(_ type: T.Type) throws {
        let name = typeName(for: type)
        let fetchDescriptor = descriptor(typeName: name)

        let items = try modelContext.fetch(fetchDescriptor)
        for item in items {
            modelContext.delete(item)
        }

        try modelContext.save()
    }
}

// MARK: - Shared Instance

public extension SwiftDataStorable {
    @MainActor static var shared: SwiftDataStorable!

    /// Factory that creates an instance from a configured `ModelContainer`.
    /// Provided because `@ModelActor` may synthesize a non-public initializer.
    static func make(modelContainer: ModelContainer) -> SwiftDataStorable {
        SwiftDataStorable(modelContainer: modelContainer)
    }
}
