import Foundation

/// The tip jar's In-App Purchase catalog: three consumables that unlock
/// nothing. Product IDs must match App Store Connect and `Configs/TipJar.storekit`.
enum TipJarCatalog {

    enum Tip: String, CaseIterable, Sendable {
        case coffee = "zeroSixteen.stackconnect.tip.coffee"
        case snack = "zeroSixteen.stackconnect.tip.snack"
        case lunch = "zeroSixteen.stackconnect.tip.lunch"

        var emoji: String {
            switch self {
            case .coffee: return "☕"
            case .snack: return "🥪"
            case .lunch: return "🍝"
            }
        }
    }

    /// Every tip product ID, cheapest first.
    static let productIDs: [String] = Tip.allCases.map(\.rawValue)

    /// The emoji shown next to `productID`; a heart for an ID outside the catalog.
    static func emoji(for productID: String) -> String {
        Tip(rawValue: productID)?.emoji ?? "❤️"
    }

    static func contains(_ productID: String) -> Bool {
        Tip(rawValue: productID) != nil
    }
}
