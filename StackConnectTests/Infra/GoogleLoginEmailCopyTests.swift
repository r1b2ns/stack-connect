import XCTest
@testable import StackConnect

/// The signed-in Google account's e-mail in the Google Play copy (follow-up
/// B3): where it comes from, and the footers that name it.
@MainActor
final class GoogleLoginEmailCopyTests: XCTestCase {

    private var keychain: MockKeyStorable!
    private let signIn = AccountModel(id: "play.signin", name: "Play", providerType: .googlePlay, authMethod: .googleSignIn)

    override func setUp() async throws {
        try await super.setUp()
        keychain = MockKeyStorable()
    }

    func testTheEmailComesFromTheAccountsGoogleLogin() {
        keychain.setObject(GooglePlayCredentials(googleLoginId: "user-1"), forKey: "credentials.\(signIn.id)")
        GoogleLoginKeychainStore(keychain: keychain).save(GoogleAuthFixtures.grant(email: "dev@example.com"))

        XCTAssertEqual(GoogleLoginReferences.email(of: signIn, keychain: keychain), "dev@example.com")
    }

    func testNoEmailWithoutALoginOrForAServiceAccount() {
        XCTAssertNil(GoogleLoginReferences.email(of: signIn, keychain: keychain), "no credentials")

        keychain.setObject(GooglePlayCredentials(googleLoginId: "user-1"), forKey: "credentials.\(signIn.id)")
        XCTAssertNil(GoogleLoginReferences.email(of: signIn, keychain: keychain), "no stored grant")

        GoogleLoginKeychainStore(keychain: keychain).save(GoogleAuthFixtures.grant(email: nil))
        XCTAssertNil(GoogleLoginReferences.email(of: signIn, keychain: keychain), "Google sent no e-mail")

        let serviceAccount = AccountModel(id: "play.sa", name: "SA", providerType: .googlePlay)
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()), forKey: "credentials.play.sa")
        XCTAssertNil(GoogleLoginReferences.email(of: serviceAccount, keychain: keychain))
    }

    func testUsersFootersNameTheEmail() {
        var users = GooglePlayUsersUiState(account: signIn)
        users.googleAccountEmail = "dev@example.com"
        XCTAssertEqual(
            users.developerIdFooter,
            String(localized: "Google doesn't tell StackConnect which developer account to use: the ID is in Play Console › Settings › Developer account (and in every Play Console URL). The Google account \("dev@example.com") needs the “Admin (all permissions)” permission to manage users.")
        )

        var detail = GooglePlayUserDetailUiState(account: signIn, user: GooglePlayUserModel(email: "partial@x.example", partial: true), serviceAccountEmail: nil)
        detail.googleAccountEmail = "dev@example.com"
        XCTAssertEqual(
            detail.partialAccessFooter,
            String(localized: "Google returned only part of this user's access (they also have access the Google account \("dev@example.com") can't see). Edit them in Play Console.")
        )
    }
}
