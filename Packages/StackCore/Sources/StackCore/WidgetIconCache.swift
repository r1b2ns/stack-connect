import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// Shared cache of app-icon bitmaps living inside the App Group container so the
/// widget extension can render real icons (WidgetKit can't fetch remote images at
/// render time). The app writes icons after a sync; the widget reads them.
///
/// Files are keyed by a stable hash of the icon URL, so a changed URL produces a
/// new file and triggers a re-download.
public enum WidgetIconCache {

    /// Max edge length (in pixels) icons are downscaled to before caching, keeping
    /// the per-entry payload small for WidgetKit.
    private static let maxPixelSize: CGFloat = 128

    // MARK: - Paths

    public static func directory() -> URL? {
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) else { return nil }
        let dir = base.appendingPathComponent("WidgetIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func fileURL(forIconURL urlString: String) -> URL? {
        guard let dir = directory() else { return nil }
        return dir.appendingPathComponent("\(stableKey(urlString)).png")
    }

    // MARK: - Read

    /// Returns cached icon bytes for an icon URL, if present.
    public static func iconData(forIconURL urlString: String?) -> Data? {
        guard let urlString, let fileURL = fileURL(forIconURL: urlString) else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    // MARK: - Write

    /// Downloads and caches any icons not already present. Existing files are left
    /// untouched. Safe to call after every sync.
    public static func preload(iconURLs: [String]) async {
        let unique = Set(iconURLs.filter { !$0.isEmpty })
        for urlString in unique {
            guard let fileURL = fileURL(forIconURL: urlString) else { continue }
            if FileManager.default.fileExists(atPath: fileURL.path) { continue }
            guard let remote = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: remote)
                guard let png = downscaledPNG(from: data) else { continue }
                try png.write(to: fileURL, options: .atomic)
            } catch {
                Log.print.warning("[WidgetIconCache] Failed to cache icon: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private static func stableKey(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func downscaledPNG(from data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxPixelSize / longest)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.pngData()
        #else
        return data
        #endif
    }
}
