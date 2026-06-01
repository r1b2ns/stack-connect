import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// Read-only tool: returns the most recent customer reviews cached on the
/// device for a single app. Resolves the app by name, disambiguates multiple
/// matches, and enforces the account's `review` view permission.
@available(iOS 26.0, *)
struct ListReviewsTool: Tool {

    let name = "list_reviews"
    let description = """
    Lists the most recent customer App Store reviews cached on this device for \
    one app. Use it to answer questions about ratings or what users are saying \
    about a specific app.
    """

    @Generable
    struct Arguments {
        @Guide(description: "The name (or part of the name) of the app to get reviews for.")
        var appName: String

        @Guide(description: "Maximum number of reviews to return. Prefer a small number such as 5.")
        var limit: Int
    }

    let resolver: any AppResolving
    let storage: any PersistentStorable

    func call(arguments: Arguments) async throws -> String {
        await run(appName: arguments.appName, limit: arguments.limit)
    }

    /// Core logic, decoupled from the generated `Arguments` type for testing.
    func run(appName: String, limit: Int) async -> String {
        let matches = await resolver.apps(matching: appName)

        guard !matches.isEmpty else {
            return "No app matches “\(appName)”. Ask the user to check the app name."
        }
        guard matches.count == 1, let app = matches.first else {
            let names = matches.prefix(8).map(\.name).joined(separator: ", ")
            return "Multiple apps match “\(appName)”: \(names). Ask the user which one they mean."
        }

        if let account = await resolver.account(for: app), !account.canView(.review) {
            return "You don't have permission to view reviews for \(app.name)."
        }

        let cappedLimit = min(max(limit <= 0 ? 5 : limit, 1), 20)
        let cached = (try? await storage.fetchAll(CustomerReviewModel.self)) ?? []
        let reviews = cached
            .filter { $0.appId == app.id }
            .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
            .prefix(cappedLimit)

        guard !reviews.isEmpty else {
            return "No reviews are cached for \(app.name) yet. They will appear after the next sync."
        }

        let formatted = reviews.map(Self.format).joined(separator: "\n\n")
        return "Most recent reviews for \(app.name):\n\n\(formatted)"
    }

    private static func format(_ review: CustomerReviewModel) -> String {
        let clamped = max(0, min(review.rating, 5))
        let stars = String(repeating: "★", count: clamped)
            + String(repeating: "☆", count: 5 - clamped)

        var header = "\(stars) (\(review.rating)/5)"
        if let title = review.title, !title.isEmpty {
            header += " — “\(title)”"
        }

        var meta: [String] = []
        if let nickname = review.reviewerNickname, !nickname.isEmpty { meta.append(nickname) }
        if let territory = review.territory, !territory.isEmpty { meta.append(territory) }
        if let date = review.createdDate {
            meta.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if !meta.isEmpty {
            header += "\n" + meta.joined(separator: " · ")
        }

        var result = header
        if let body = review.body, !body.isEmpty {
            result += "\n\(body)"
        }
        if review.hasResponse {
            result += "\n↳ Developer has responded."
        }
        return result
    }
}
#endif
