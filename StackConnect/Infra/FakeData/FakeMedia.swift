#if DEBUG
import UIKit

/// Deterministic, locally rendered images for fake data mode: app icons and
/// store screenshots. Fake records point at `https://media.fakedata.example/…`
/// URLs (`.example` is reserved, so they can never reach a real host) and
/// `FakeNetworkURLProtocol` answers them with a PNG drawn here — the screens
/// keep loading images through `AsyncImage` / `URLSession` as usual.
enum FakeMedia {

    static let host = "media.fakedata.example"

    /// A colored tile with a white SF Symbol (or the first letter of `name`
    /// when the symbol doesn't exist), the look of a real app icon.
    static func iconURL(name: String, symbol: String, color: String) -> String {
        url(kind: "icon", key: name, items: [
            "name": name, "symbol": symbol, "color": color
        ])
    }

    /// A store screenshot mock: gradient in the app color, the symbol, a
    /// headline and a fake phone UI. `width` × `height` are pixels.
    static func screenshotURL(appName: String, symbol: String, color: String, caption: String, width: Int, height: Int) -> String {
        url(kind: "screenshot", key: "\(appName)-\(caption)-\(width)x\(height)", items: [
            "name": appName, "symbol": symbol, "color": color, "caption": caption,
            "w": String(width), "h": String(height)
        ])
    }

    // MARK: - Rendering

    /// PNG for a `FakeMedia` URL, or `nil` when the URL isn't one.
    static func pngData(for url: URL) -> Data? {
        guard url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { _, last in last }
        )
        let name = items["name"] ?? "App"
        let symbol = items["symbol"] ?? "app.fill"
        let color = UIColor(fakeHex: items["color"] ?? "3366CC")

        if url.path.hasPrefix("/icon/") {
            return renderIcon(name: name, symbol: symbol, color: color)
        }
        if url.path.hasPrefix("/screenshot/") {
            let width = Int(items["w"] ?? "") ?? 1290
            let height = Int(items["h"] ?? "") ?? 2796
            return renderScreenshot(name: name, symbol: symbol, color: color, caption: items["caption"] ?? name,
                                    size: CGSize(width: width, height: height))
        }
        return nil
    }

    private static func url(kind: String, key: String, items: [String: String]) -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        let slug = key.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        components.path = "/\(kind)/\(slug).png"
        components.queryItems = items.keys.sorted().map { URLQueryItem(name: $0, value: items[$0]) }
        return components.url?.absoluteString ?? "https://\(host)/\(kind)/\(slug).png"
    }

    private static func renderIcon(name: String, symbol: String, color: UIColor) -> Data? {
        let size = CGSize(width: 512, height: 512)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            drawGradient(in: CGRect(origin: .zero, size: size), color: color, context: context.cgContext)
            drawGlyph(symbol: symbol, fallbackText: String(name.prefix(1)).uppercased(),
                      in: CGRect(x: 116, y: 116, width: 280, height: 280))
        }
        return image.pngData()
    }

    private static func renderScreenshot(name: String, symbol: String, color: UIColor, caption: String, size: CGSize) -> Data? {
        // Screens only show thumbnails / a fitted preview: render at a third of
        // the declared size (same aspect ratio) to keep it fast and small.
        let scale: CGFloat = 1.0 / 3.0
        let canvas = CGSize(width: max(size.width * scale, 120), height: max(size.height * scale, 120))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: canvas)
            drawGradient(in: bounds, color: color, context: context.cgContext)

            let unit = min(canvas.width, canvas.height)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let title = NSAttributedString(string: caption, attributes: [
                .font: UIFont.systemFont(ofSize: unit * 0.085, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ])
            let titleRect = CGRect(x: unit * 0.08, y: canvas.height * 0.07, width: canvas.width - unit * 0.16, height: unit * 0.3)
            title.draw(with: titleRect, options: [.usesLineFragmentOrigin], context: nil)

            // A device-like card with the app's glyph and a few placeholder rows.
            let card = CGRect(x: canvas.width * 0.12, y: canvas.height * 0.3,
                              width: canvas.width * 0.76, height: canvas.height * 0.62)
            UIColor.white.withAlphaComponent(0.92).setFill()
            UIBezierPath(roundedRect: card, cornerRadius: unit * 0.06).fill()

            let glyphSide = min(card.width, card.height) * 0.32
            drawGlyph(symbol: symbol, fallbackText: String(name.prefix(1)).uppercased(),
                      in: CGRect(x: card.midX - glyphSide / 2, y: card.minY + card.height * 0.1, width: glyphSide, height: glyphSide),
                      tint: color)
            color.withAlphaComponent(0.25).setFill()
            for row in 0..<4 {
                let rowRect = CGRect(x: card.minX + card.width * 0.1,
                                     y: card.minY + card.height * (0.5 + CGFloat(row) * 0.11),
                                     width: card.width * (row.isMultiple(of: 2) ? 0.8 : 0.6),
                                     height: card.height * 0.05)
                UIBezierPath(roundedRect: rowRect, cornerRadius: rowRect.height / 2).fill()
            }
        }
        return image.pngData()
    }

    private static func drawGradient(in rect: CGRect, color: UIColor, context: CGContext) {
        let top = color.fakeAdjusted(brightness: 1.18)
        let bottom = color.fakeAdjusted(brightness: 0.78)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [top.cgColor, bottom.cgColor] as CFArray,
            locations: [0, 1]
        ) else {
            color.setFill()
            context.fill(rect)
            return
        }
        context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                                   end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    }

    private static func drawGlyph(symbol: String, fallbackText: String, in rect: CGRect, tint: UIColor = .white) {
        let configuration = UIImage.SymbolConfiguration(pointSize: rect.height * 0.8, weight: .semibold)
        if let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?
            .withTintColor(tint, renderingMode: .alwaysOriginal) {
            let aspect = glyph.size.width / max(glyph.size.height, 1)
            var target = rect
            if aspect > 1 {
                target.size.height = rect.width / aspect
                target.origin.y = rect.midY - target.height / 2
            } else {
                target.size.width = rect.height * aspect
                target.origin.x = rect.midX - target.width / 2
            }
            glyph.draw(in: target)
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSAttributedString(string: fallbackText, attributes: [
            .font: UIFont.systemFont(ofSize: rect.height * 0.75, weight: .heavy),
            .foregroundColor: tint,
            .paragraphStyle: paragraph
        ])
        text.draw(in: rect.offsetBy(dx: 0, dy: rect.height * 0.04))
    }
}

private extension UIColor {

    /// `RRGGBB` hex (no `#`); falls back to a neutral blue.
    convenience init(fakeHex hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x3366CC
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    func fakeAdjusted(brightness factor: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation, brightness: min(brightness * factor, 1), alpha: alpha)
    }
}
#endif
