import Foundation

/// Builds the plaintext JSON payload for an account `.scexport` file.
///
/// Single source of truth for the export payload shape, shared by every export
/// call site so the serialization can never diverge (DRY + Open/Closed). The
/// caller assembles the provider-specific `credentials` dict (from its keychain
/// read) and passes it in; this builder is pure and has no keychain/storage
/// dependency, which keeps it trivially testable.
enum AccountExportPayloadBuilder {

    /// Assembles the export dictionary and serializes it to a pretty-printed JSON
    /// string. Returns `nil` if serialization fails.
    ///
    /// Backward-compat contract: `appsBundles` is written **only when non-empty**.
    /// nil / empty ⇒ the key is omitted ⇒ importers treat it as "all apps".
    static func makeJSON(
        account: AccountModel,
        exportName: String,
        rules: AccountRules,
        expirationDate: Date?,
        appsBundles: [String]?,
        credentials: [String: String]?
    ) -> String? {
        var exportDict: [String: Any] = [
            "id": account.id,
            "name": exportName,
            "providerType": account.providerType.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: account.createdAt)
        ]

        exportDict["rules"] = [
            "apps": rules.apps.map(\.rawValue),
            "version": rules.version.map(\.rawValue),
            "users": rules.users.map(\.rawValue),
            "review": rules.review.map(\.rawValue),
            "testFlight": rules.testFlight.map(\.rawValue),
            "analytics": rules.analytics.map(\.rawValue),
            "provisioning": rules.provisioning.map(\.rawValue)
        ]

        exportDict["role"] = account.role.rawValue

        if let expirationDate {
            exportDict["expirationDate"] = ISO8601DateFormatter().string(from: expirationDate)
        }

        // Only a non-empty selection restricts. nil/empty ⇒ omit the key so
        // older importers keep treating the file as "all apps allowed".
        if let appsBundles, !appsBundles.isEmpty {
            exportDict["appsBundles"] = appsBundles
        }

        if let credentials, !credentials.isEmpty {
            exportDict["credentials"] = credentials
        }

        guard let data = try? JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return json
    }
}
