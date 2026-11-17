#if DEBUG
import Foundation
import Security
import SwiftData

/// The fake accounts and their (placeholder) credentials.
///
/// Only the `AccountModel`s are written to the fake SwiftData store; apps,
/// versions, reviews, caches… are filled by the app's own sync paths from the
/// fake providers, exactly as with real accounts. One exception: the Google
/// Play tracks cache, which only an edit-based read fills (the user opening
/// Tracks), is seeded as if Tracks had been opened yesterday, so the Home shows
/// the staged rollout percentages (plan H3).
enum FakeDataSeeder {

    /// Bump to re-seed existing fake stores after the seeded accounts change.
    static let seedVersion = "v3"
    static let markerTypeName = "FakeDataSeedMarker"

    enum AccountID {
        static let northwindAppStore = "fake.asc.northwind"
        static let personalAppStore = "fake.asc.personal"
        static let northwindFirebase = "fake.firebase.northwind"
        static let northwindGooglePlay = "fake.play.northwind"
    }

    static func accounts(clock: FakeClock) -> [AccountModel] {
        [
            AccountModel(id: AccountID.northwindAppStore, name: "Northwind Labs", providerType: .apple,
                         createdAt: clock.date(daysAgo: 420), role: .admin),
            AccountModel(id: AccountID.personalAppStore, name: "Jordan Avery (Personal)", providerType: .apple,
                         createdAt: clock.date(daysAgo: 180), role: .appManager),
            AccountModel(id: AccountID.northwindFirebase, name: "Northwind Labs", providerType: .firebase,
                         createdAt: clock.date(daysAgo: 300), role: .admin),
            AccountModel(id: AccountID.northwindGooglePlay, name: "Northwind Labs", providerType: .googlePlay,
                         createdAt: clock.date(daysAgo: 90),
                         googlePlayDeveloperId: FakeGooglePlayCatalog.northwindDeveloperId)
        ]
    }

    // MARK: - SwiftData

    /// Seeds the fake store unless it was already seeded with this version.
    /// Runs synchronously at launch (before any screen reads the store).
    @MainActor
    static func seedIfNeeded(container: ModelContainer, clock: FakeClock) throws {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<PersistedItem>())
        if existing.contains(where: { $0.typeName == markerTypeName && $0.identifier == seedVersion }) { return }

        try context.delete(model: PersistedItem.self)
        let encoder = JSONEncoder()
        for account in accounts(clock: clock) {
            context.insert(PersistedItem(typeName: String(describing: AccountModel.self), identifier: account.id,
                                         payload: try encoder.encode(account)))
        }
        for cache in googlePlayTracksCaches(clock: clock) {
            context.insert(PersistedItem(typeName: String(describing: GooglePlayTracksCache.self), identifier: cache.cacheKey,
                                         payload: try encoder.encode(cache)))
        }
        context.insert(PersistedItem(typeName: markerTypeName, identifier: seedVersion, payload: Data()))
        try context.save()
        Log.print.notice("[FakeData] Seeded \(accounts(clock: clock).count) fake accounts")
    }

    /// Stores `developerId` verbatim (empty clears it) on the fake Play account,
    /// bypassing `GooglePlayDeveloperId.normalized` — `-StackFakePlayDeveloperId`.
    @MainActor
    static func setPlayDeveloperId(_ developerId: String, container: ModelContainer) throws {
        let context = ModelContext(container)
        let typeName = String(describing: AccountModel.self)
        let id = AccountID.northwindGooglePlay
        let items = try context.fetch(FetchDescriptor<PersistedItem>())
        guard let item = items.first(where: { $0.typeName == typeName && $0.identifier == id }) else { return }
        let account = try JSONDecoder().decode(AccountModel.self, from: item.payload)
        let updated = account.updating(googlePlayDeveloperId: .some(developerId.isEmpty ? nil : developerId))
        item.payload = try JSONEncoder().encode(updated)
        try context.save()
        Log.print.notice("[FakeData] Play developer ID forced to \"\(developerId, privacy: .public)\"")
    }

    /// The tracks of every fake Play app, read "yesterday".
    static func googlePlayTracksCaches(clock: FakeClock) -> [GooglePlayTracksCache] {
        FakeGooglePlayCatalog.apps.map { app in
            GooglePlayTracksCache(
                accountId: AccountID.northwindGooglePlay,
                packageName: app.packageName,
                tracks: app.tracks.map(GooglePlayAccountConnection.mapTrack),
                fetchedAt: clock.date(daysAgo: 1)
            )
        }
    }

    // MARK: - Credentials

    /// Writes every fake account's credentials into `keys`, under the same
    /// `credentials.{accountId}` keys the real Keychain uses.
    static func writeCredentials(into keys: KeyStorable) {
        keys.setObject(
            AppleCredentials(issuerID: FakeAppStoreConnectCatalog.northwindIssuerId, privateKeyID: "NWL4B5K3Y7",
                             privateKey: placeholderPEM(label: "Northwind Labs App Store Connect")),
            forKey: "credentials.\(AccountID.northwindAppStore)"
        )
        keys.setObject(
            AppleCredentials(issuerID: FakeAppStoreConnectCatalog.personalIssuerId, privateKeyID: "JAV8R2T6Q4",
                             privateKey: placeholderPEM(label: "Jordan Avery App Store Connect")),
            forKey: "credentials.\(AccountID.personalAppStore)"
        )
        keys.setObject(
            GooglePlayCredentials(serviceAccountJSON: serviceAccountJSON(
                projectId: FakeGooglePlayCatalog.northwindProjectId,
                clientEmail: FakeGooglePlayCatalog.northwindClientEmail,
                privateKey: placeholderPEM(label: "Northwind Labs Google Play")
            )),
            forKey: "credentials.\(AccountID.northwindGooglePlay)"
        )
        // `FirebaseConfiguration` parses the RSA key eagerly, so Firebase gets a
        // throwaway key generated on device (never sent anywhere).
        if let firebaseKey = generatedRSAPrivateKeyPEM() {
            keys.setObject(
                FirebaseCredentials(serviceAccountJSON: serviceAccountJSON(
                    projectId: FakeFirebaseCatalog.trailhead.projectId,
                    clientEmail: FakeFirebaseCatalog.northwindClientEmail,
                    privateKey: firebaseKey
                )),
                forKey: "credentials.\(AccountID.northwindFirebase)"
            )
        } else {
            Log.print.error("[FakeData] Could not generate the Firebase demo key; the Firebase account will show no projects")
        }
    }

    static func serviceAccountJSON(projectId: String, clientEmail: String, privateKey: String) -> String {
        let object: [String: String] = [
            "type": "service_account",
            "project_id": projectId,
            "private_key_id": "fake0\(abs(FakeAppStoreConnectCatalog.hash(clientEmail)) % 1_000_000_000)",
            "private_key": privateKey,
            "client_email": clientEmail,
            "client_id": String(abs(FakeAppStoreConnectCatalog.hash(projectId)) % 1_000_000_000_000),
            "auth_uri": "https://oauth.fakedata.example/auth",
            "token_uri": "https://oauth.fakedata.example/token",
            "auth_provider_x509_cert_url": "https://oauth.fakedata.example/certs",
            "client_x509_cert_url": "https://oauth.fakedata.example/certs/\(clientEmail)"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Looks like a PEM, is not a key: the fake core providers never parse it.
    private static func placeholderPEM(label: String) -> String {
        let body = Data("FAKE DATA MODE - \(label) - NOT A REAL KEY".utf8).base64EncodedString()
        return "-----BEGIN PRIVATE KEY-----\n\(body)\n-----END PRIVATE KEY-----"
    }

    /// A fresh 2048-bit RSA key in PKCS#1 PEM.
    private static func generatedRSAPrivateKeyPEM() -> String? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecAttrIsPermanent as String: false
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let der = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            return nil
        }
        let base64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN RSA PRIVATE KEY-----\n\(base64)\n-----END RSA PRIVATE KEY-----"
    }
}
#endif
