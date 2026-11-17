import Foundation

/// Builds tappable links from text the app didn't write (e.g. a Play listing's
/// website or promo video), allowing only the schemes a link is meant to open.
///
/// A store field can hold any URL — `javascript:`, `file:`, another app's
/// custom scheme. Handed to `Link`/`openURL` as is, that could launch an
/// arbitrary app or action, so anything outside the allowed scheme gets no
/// link (the text is still shown).
enum ExternalLinkURL {

    private static let webSchemes: Set<String> = ["http", "https"]

    /// An `http`/`https` page with a host. A value without a scheme (Google
    /// often keeps `example.com`) is opened over `https`; any other scheme is
    /// refused.
    static func web(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: URL?
        if let url = URL(string: trimmed), url.scheme != nil {
            candidate = url
        } else {
            candidate = URL(string: "https://\(trimmed)")
        }

        guard let url = candidate,
              let scheme = url.scheme?.lowercased(), webSchemes.contains(scheme),
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    /// A `mailto:` link for a plain address (no spaces, one `@`, no extra
    /// `mailto` parameters).
    static func email(_ raw: String) -> URL? {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }),
              !address.contains(where: { $0.isWhitespace || $0 == "?" || $0 == "/" || $0 == ":" }) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        return components.url
    }

    /// A `tel:` link keeping only dialable characters (digits and `+`).
    static func phone(_ raw: String) -> URL? {
        let dialable = raw.filter { $0.isASCII && ($0.isNumber || $0 == "+") }
        return dialable.isEmpty ? nil : URL(string: "tel:\(dialable)")
    }
}
