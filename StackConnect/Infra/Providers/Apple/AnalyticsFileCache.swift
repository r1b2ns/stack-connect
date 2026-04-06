import Foundation

/// Manages local file cache for analytics report TSV/CSV data.
/// Files are cached per app with a 24-hour TTL.
///
/// Directory structure:
/// ```
/// Caches/analytics/{appId}/
/// ├── app_installs_deletes.tsv
/// ├── app_store_engagement.tsv
/// └── cache_meta.json
/// ```
struct AnalyticsFileCache {

    // TODO: Restore to 24 * 60 * 60 when ready to enable cache
    private static let cacheTTL: TimeInterval = 0 // Cache disabled — always re-download
    private static let metaFileName = "cache_meta.json"

    // MARK: - Cache Validation

    /// Returns true if a cached file exists and is less than 24 hours old.
    static func isCacheValid(appId: String, reportType: String) -> Bool {
        guard let meta = loadMeta(appId: appId),
              let dateString = meta[reportType],
              let cachedDate = ISO8601DateFormatter().date(from: dateString) else {
            return false
        }

        let age = Date().timeIntervalSince(cachedDate)
        let fileExists = FileManager.default.fileExists(atPath: tsvPath(appId: appId, reportType: reportType).path)

        return age < cacheTTL && fileExists
    }

    // MARK: - Save

    /// Saves TSV content to the cache directory and updates metadata.
    static func saveTSV(appId: String, reportType: String, content: String) {
        let dir = cacheDirectory(appId: appId)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Write TSV file
        let filePath = tsvPath(appId: appId, reportType: reportType)
        try? content.write(to: filePath, atomically: true, encoding: .utf8)

        // Update metadata
        var meta = loadMeta(appId: appId) ?? [:]
        meta[reportType] = ISO8601DateFormatter().string(from: Date())
        saveMeta(appId: appId, meta: meta)

        Log.print.info("[AnalyticsCache] Saved \(reportType) for app \(appId) (\(content.count) bytes)")
    }

    // MARK: - Load

    /// Loads cached TSV content. Returns nil if not found.
    static func loadTSV(appId: String, reportType: String) -> String? {
        let filePath = tsvPath(appId: appId, reportType: reportType)
        guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
            return nil
        }
        Log.print.info("[AnalyticsCache] Loaded \(reportType) from cache for app \(appId)")
        return content
    }

    // MARK: - Clear

    /// Deletes all cached files for an app.
    static func clearCache(appId: String) {
        let dir = cacheDirectory(appId: appId)
        try? FileManager.default.removeItem(at: dir)
        Log.print.info("[AnalyticsCache] Cleared cache for app \(appId)")
    }

    /// Deletes a specific report's cached file.
    static func clearReport(appId: String, reportType: String) {
        let filePath = tsvPath(appId: appId, reportType: reportType)
        try? FileManager.default.removeItem(at: filePath)

        // Update meta
        var meta = loadMeta(appId: appId) ?? [:]
        meta.removeValue(forKey: reportType)
        saveMeta(appId: appId, meta: meta)
    }

    // MARK: - Export

    /// Returns all cached TSV file URLs for an app.
    static func allCachedFiles(appId: String) -> [URL] {
        let dir = cacheDirectory(appId: appId)
        let fm = FileManager.default

        guard fm.fileExists(atPath: dir.path) else { return [] }

        do {
            return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "tsv" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            Log.print.error("[AnalyticsCache] Failed to list files: \(error.localizedDescription)")
            return []
        }
    }

    /// Creates a zip archive of all cached TSV files using the system's built-in zip.
    /// Returns the zip URL or nil.
    static func exportAsZip(appId: String) -> URL? {
        let files = allCachedFiles(appId: appId)
        guard !files.isEmpty else { return nil }

        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        let zipName = "analytics-\(appId)-\(dateStr).zip"
        let zipURL = fm.temporaryDirectory.appendingPathComponent(zipName)

        try? fm.removeItem(at: zipURL)

        // Copy files to a temp directory, then zip
        let tempDir = fm.temporaryDirectory.appendingPathComponent("analytics_export_\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for file in files {
            let dest = tempDir.appendingPathComponent(file.lastPathComponent)
            try? fm.copyItem(at: file, to: dest)
        }

        // Use NSFileCoordinator to create a zip
        var error: NSError?
        let coordinator = NSFileCoordinator()
        var resultURL: URL?

        coordinator.coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { zippedURL in
            let destination = zipURL
            try? fm.removeItem(at: destination)
            try? fm.moveItem(at: zippedURL, to: destination)
            resultURL = destination
        }

        // Cleanup temp dir
        try? fm.removeItem(at: tempDir)

        if let error {
            Log.print.error("[AnalyticsCache] Zip failed: \(error.localizedDescription)")
            return nil
        }

        Log.print.info("[AnalyticsCache] Created zip: \(zipURL.lastPathComponent) with \(files.count) files")
        return resultURL
    }

    // MARK: - Private

    private static func cacheDirectory(appId: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("analytics/\(appId)", isDirectory: true)
    }

    private static func tsvPath(appId: String, reportType: String) -> URL {
        cacheDirectory(appId: appId).appendingPathComponent("\(reportType).tsv")
    }

    private static func metaPath(appId: String) -> URL {
        cacheDirectory(appId: appId).appendingPathComponent(metaFileName)
    }

    private static func loadMeta(appId: String) -> [String: String]? {
        let path = metaPath(appId: appId)
        guard let data = try? Data(contentsOf: path),
              let meta = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return meta
    }

    private static func saveMeta(appId: String, meta: [String: String]) {
        let path = metaPath(appId: appId)
        let dir = cacheDirectory(appId: appId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: path)
        }
    }
}
