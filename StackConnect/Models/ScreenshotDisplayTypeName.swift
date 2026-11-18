import Foundation

/// Human-readable, localized labels for App Store Connect screenshot display types
/// (`ScreenshotDisplayType`, e.g. `APP_IPHONE_67`, `IMESSAGE_APP_IPAD_105`) and
/// app preview types (`PreviewType`, e.g. `IPHONE_67`, `DESKTOP`).
///
/// The raw ids are not meant for display ("Iphone 67"), so every known device key
/// is mapped to the name ASC uses — `APP_IPHONE_67` → `iPhone 6.7" Display`. The
/// screen size is formatted with the current locale (6,7 in German). Unknown ids
/// fall back to a humanized form with Apple product casing.
enum ScreenshotDisplayTypeName {

    private enum Device {
        /// A display of `inches` on `product`, e.g. `iPhone 6.7" Display`.
        case display(product: String, inches: Double)
        /// A named product without a size, e.g. `Mac`, `Apple Watch Ultra`.
        case product(String)
    }

    /// Localized label for a screenshot display type or app preview type id.
    static func displayName(for rawType: String?) -> String {
        guard let rawType, !rawType.isEmpty else {
            return String(localized: "Unknown", comment: "Unknown screenshot display size")
        }

        var key = rawType
        var isIMessage = false
        if key.hasPrefix("IMESSAGE_APP_") {
            key.removeFirst("IMESSAGE_APP_".count)
            isIMessage = true
        } else if key.hasPrefix("APP_") {
            key.removeFirst("APP_".count)
        }

        let name: String
        if let device = device(for: key) {
            name = label(for: device)
        } else {
            name = humanize(key)
        }
        return isIMessage ? String(localized: "\(name) (iMessage)", comment: "Screenshot display size for an iMessage app, e.g. iPhone 6.7\" Display (iMessage)") : name
    }

    // MARK: - Private

    private static func device(for key: String) -> Device? {
        switch key {
        case "IPHONE_67":           return .display(product: "iPhone", inches: 6.7)
        case "IPHONE_65":           return .display(product: "iPhone", inches: 6.5)
        case "IPHONE_61":           return .display(product: "iPhone", inches: 6.1)
        case "IPHONE_58":           return .display(product: "iPhone", inches: 5.8)
        case "IPHONE_55":           return .display(product: "iPhone", inches: 5.5)
        case "IPHONE_47":           return .display(product: "iPhone", inches: 4.7)
        case "IPHONE_40":           return .display(product: "iPhone", inches: 4.0)
        case "IPHONE_35":           return .display(product: "iPhone", inches: 3.5)
        case "IPAD_PRO_3GEN_129":   return .display(product: "iPad Pro", inches: 12.9)
        case "IPAD_PRO_3GEN_11":    return .display(product: "iPad Pro", inches: 11)
        case "IPAD_PRO_129":        return .display(product: String(localized: "iPad Pro (2nd generation)", comment: "Apple device model name"), inches: 12.9)
        case "IPAD_105":            return .display(product: "iPad", inches: 10.5)
        case "IPAD_97":             return .display(product: "iPad", inches: 9.7)
        case "DESKTOP":             return .product("Mac")
        case "APPLE_TV":            return .product("Apple TV")
        case "APPLE_VISION_PRO":    return .product("Apple Vision Pro")
        case "WATCH_ULTRA":         return .product("Apple Watch Ultra")
        case "WATCH_SERIES_10":     return .product("Apple Watch Series 10")
        case "WATCH_SERIES_7":      return .product("Apple Watch Series 7")
        case "WATCH_SERIES_4":      return .product("Apple Watch Series 4")
        case "WATCH_SERIES_3":      return .product("Apple Watch Series 3")
        default:                    return nil
        }
    }

    private static func label(for device: Device) -> String {
        switch device {
        case .product(let name):
            return name
        case .display(let product, let inches):
            let size = inches.formatted(.number.precision(.fractionLength(0...1)))
            return String(localized: "\(product) \(size)\" Display", comment: "Screenshot display size, e.g. iPhone 6.7\" Display. First argument is the device, second the screen size in inches.")
        }
    }

    /// Fallback for ids this mapping does not know: `IPAD_PRO_M4` → "iPad Pro M4".
    private static func humanize(_ key: String) -> String {
        let brandCasing: [String: String] = [
            "IPHONE": "iPhone", "IPAD": "iPad", "IMESSAGE": "iMessage", "TV": "TV",
            "DESKTOP": "Mac", "PRO": "Pro"
        ]
        return key.split(separator: "_")
            .map { brandCasing[String($0)] ?? $0.capitalized }
            .joined(separator: " ")
    }
}
