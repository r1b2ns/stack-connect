import Foundation

/// Zips a directory into a `.zip` using `NSFileCoordinator`'s `.forUploading`
/// option — no third-party dependency. Shared by the screenshots export and the
/// analytics files export.
enum FileArchiver {

    /// Produces a `.zip` of `source` in the temporary directory and returns its
    /// URL. `nonisolated` so it can run off the main actor via `Task.detached`.
    nonisolated static func zipDirectory(_ source: URL) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var copyError: Error?
        var resultURL: URL?

        coordinator.coordinate(readingItemAt: source, options: [.forUploading], error: &coordinatorError) { zippedURL in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(source.lastPathComponent).zip")
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zippedURL, to: destination)
                resultURL = destination
            } catch {
                copyError = error
            }
        }

        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        guard let resultURL else {
            throw NSError(
                domain: "FileArchiver",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to create the zip file.")]
            )
        }
        return resultURL
    }
}
