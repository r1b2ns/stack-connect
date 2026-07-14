import Foundation

/// A reusable, user-authored reply message for App Store customer reviews.
///
/// Templates are entirely local: they are persisted through `PersistentStorable`
/// and never sent to or read from the App Store Connect API. Each template is
/// scoped to a single account via `accountId`.
struct ReplyTemplateModel: Codable, Identifiable, Hashable {
    let id: String
    let accountId: String
    var title: String
    var body: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        accountId: String,
        title: String,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
