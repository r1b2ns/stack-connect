import Foundation

// MARK: - Protocol

/// On-device persistence of the network audit log.
protocol NetworkAuditStoring: Sendable {
    func append(_ event: NetworkAuditEvent) async
    /// Summaries recorded at or after `cutoff`, newest first.
    func summaries(since cutoff: Date) async -> [NetworkAuditEventSummary]
    func event(for summary: NetworkAuditEventSummary) async -> NetworkAuditEvent?
    /// Number of events recorded before `cutoff` (what a purge would delete).
    func count(before cutoff: Date) async -> Int
    /// Deletes every event recorded before `cutoff`. Returns how many went.
    @discardableResult
    func purge(before cutoff: Date) async -> Int
    func deleteAll() async
    func stats() async -> NetworkAuditStorageStats
    /// Rewrites every stored event `transform` changes (non-`nil` result).
    /// Returns how many were rewritten.
    @discardableResult
    func rewrite(_ transform: @escaping @Sendable (NetworkAuditEvent) -> NetworkAuditEvent?) async -> Int
}

extension NetworkAuditStoring {
    func events(for summaries: [NetworkAuditEventSummary]) async -> [NetworkAuditEvent] {
        var events: [NetworkAuditEvent] = []
        events.reserveCapacity(summaries.count)
        for summary in summaries {
            if let event = await event(for: summary) {
                events.append(event)
            }
        }
        return events
    }
}

// MARK: - File store

/// Stores the log as plain files, separate from the app data:
///
/// ```
/// Application Support/NetworkAudit/
///   2026-11-24/            one folder per UTC day
///     index.jsonl          one `NetworkAuditEventSummary` per line (the list)
///     <uuid>.json          the full, masked `NetworkAuditEvent` (the detail)
/// ```
///
/// - Device only: never in the App Group, excluded from iCloud / iTunes
///   backups (`isExcludedFromBackup`) and never synced.
/// - File protection `completeUntilFirstUserAuthentication`: encrypted by iOS
///   until the first unlock after a restart, and still writable while locked so
///   background sync is audited too.
/// - Day folders make retention cheap: whole days older than the cutoff are
///   removed at once; only the boundary day is filtered line by line.
actor FileNetworkAuditStore: NetworkAuditStoring {

    static let shared = FileNetworkAuditStore(directory: FileNetworkAuditStore.defaultDirectory)

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("NetworkAudit", isDirectory: true)
    }

    private static let indexFileName = "index.jsonl"
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    private let directory: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Write

    func append(_ event: NetworkAuditEvent) {
        do {
            let day = try dayDirectory(for: event.date, create: true)
            let eventData = try encoder.encode(event)
            try eventData.write(to: day.appendingPathComponent("\(event.id.uuidString).json"),
                                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

            var line = try encoder.encode(event.summary)
            line.append(UInt8(ascii: "\n"))
            try appendLine(line, to: day.appendingPathComponent(Self.indexFileName))
        } catch {
            Log.print.error("[NetworkAudit] Failed to store an event: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Read

    func summaries(since cutoff: Date) -> [NetworkAuditEventSummary] {
        dayDirectories()
            .flatMap { readIndex(in: $0.url) }
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }

    func event(for summary: NetworkAuditEventSummary) -> NetworkAuditEvent? {
        guard let day = try? dayDirectory(for: summary.date, create: false) else { return nil }
        let file = day.appendingPathComponent("\(summary.id.uuidString).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? decoder.decode(NetworkAuditEvent.self, from: data)
    }

    func count(before cutoff: Date) -> Int {
        dayDirectories()
            .flatMap { readIndex(in: $0.url) }
            .filter { $0.date < cutoff }
            .count
    }

    func stats() -> NetworkAuditStorageStats {
        let summaries = dayDirectories().flatMap { readIndex(in: $0.url) }
        return NetworkAuditStorageStats(
            eventCount: summaries.count,
            byteCount: directorySize(),
            oldestDate: summaries.map(\.date).min()
        )
    }

    // MARK: - Retention

    @discardableResult
    func purge(before cutoff: Date) -> Int {
        var removed = 0
        for day in dayDirectories() {
            let summaries = readIndex(in: day.url)
            let endOfDay = day.start.addingTimeInterval(86_400)
            if endOfDay <= cutoff {
                removed += summaries.count
                try? fileManager.removeItem(at: day.url)
                continue
            }
            let expired = summaries.filter { $0.date < cutoff }
            guard !expired.isEmpty else { continue }
            for summary in expired {
                try? fileManager.removeItem(at: day.url.appendingPathComponent("\(summary.id.uuidString).json"))
            }
            let kept = summaries.filter { $0.date >= cutoff }
            rewriteIndex(kept, in: day.url)
            removed += expired.count
        }
        if removed > 0 {
            Log.print.info("[NetworkAudit] Purged \(removed) events")
        }
        return removed
    }

    @discardableResult
    func rewrite(_ transform: @escaping @Sendable (NetworkAuditEvent) -> NetworkAuditEvent?) -> Int {
        var rewritten = 0
        for day in dayDirectories() {
            var summaries = readIndex(in: day.url)
            var dayChanged = false
            for (index, summary) in summaries.enumerated() {
                let file = day.url.appendingPathComponent("\(summary.id.uuidString).json")
                guard let data = try? Data(contentsOf: file),
                      let event = try? decoder.decode(NetworkAuditEvent.self, from: data),
                      let updated = transform(event),
                      let encoded = try? encoder.encode(updated) else { continue }
                try? encoded.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                summaries[index] = updated.summary
                dayChanged = true
                rewritten += 1
            }
            if dayChanged {
                rewriteIndex(summaries, in: day.url)
            }
        }
        if rewritten > 0 {
            Log.print.info("[NetworkAudit] Rewrote \(rewritten) stored events")
        }
        return rewritten
    }

    func deleteAll() {
        try? fileManager.removeItem(at: directory)
        Log.print.info("[NetworkAudit] Deleted the whole log")
    }

    // MARK: - Private

    private func prepareRootDirectory() throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: Self.protection]
        )
        var root = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }

    private func dayDirectory(for date: Date, create: Bool) throws -> URL {
        let url = directory.appendingPathComponent(Self.dayFormatter.string(from: date), isDirectory: true)
        if create, !fileManager.fileExists(atPath: url.path) {
            try prepareRootDirectory()
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: Self.protection]
            )
        }
        return url
    }

    private func dayDirectories() -> [(url: URL, start: Date)] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.compactMap { name in
            guard let start = Self.dayFormatter.date(from: name) else { return nil }
            return (directory.appendingPathComponent(name, isDirectory: true), start)
        }
    }

    private func readIndex(in day: URL) -> [NetworkAuditEventSummary] {
        guard let data = try? Data(contentsOf: day.appendingPathComponent(Self.indexFileName)) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).compactMap {
            try? decoder.decode(NetworkAuditEventSummary.self, from: Data($0))
        }
    }

    private func rewriteIndex(_ summaries: [NetworkAuditEventSummary], in day: URL) {
        var data = Data()
        for summary in summaries {
            guard let line = try? encoder.encode(summary) else { continue }
            data.append(line)
            data.append(UInt8(ascii: "\n"))
        }
        try? data.write(to: day.appendingPathComponent(Self.indexFileName),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func appendLine(_ line: Data, to file: URL) throws {
        if !fileManager.fileExists(atPath: file.path) {
            fileManager.createFile(atPath: file.path, contents: line, attributes: [.protectionKey: Self.protection])
            return
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private func directorySize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
