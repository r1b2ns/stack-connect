import XCTest
@testable import StackConnect

/// The connection guide's copy and the method chooser's model, against the
/// App Review rules they follow: at most four pages, only the provider being
/// connected and its available methods, no password or code talk without the
/// email and password method, no "Sign in with Apple" look, no private
/// endpoint, and claims consistent with the privacy policy.
///
/// The test host runs in the simulator's language (not always English):
/// expected copy is built with `String(localized:)`, like production, and the
/// wording checks that must hold in every language read the compiled tables.
final class ConnectionGuideContentTests: XCTestCase {

    /// Every provider with every combination of its optional method.
    private var combinations: [(provider: ProviderType, methods: [AccountConnectionMethod])] {
        ProviderType.allCases.flatMap { provider in
            [true, false].map { optional in
                (provider: provider,
                 methods: AccountConnectionMethod.available(for: provider, appleIdSignIn: optional, googleSignIn: optional))
            }
        }
    }

    /// Every user-visible string of `pages`.
    private func texts(_ pages: [ConnectionGuidePage]) -> [String] {
        var texts: [String] = []
        for page in pages {
            texts.append(page.title)
            texts.append(page.message)
            for item in page.items + page.notes {
                if let title = item.title { texts.append(title) }
                texts.append(item.text)
            }
            texts.append(contentsOf: page.links.map(\.title))
            if let footnote = page.footnote { texts.append(footnote) }
        }
        return texts
    }

    private func glyphs(_ pages: [ConnectionGuidePage]) -> [String] {
        var glyphs: [String] = []
        for page in pages {
            glyphs.append(page.systemImage)
            glyphs.append(contentsOf: (page.items + page.notes).map(\.systemImage))
            glyphs.append(contentsOf: page.links.map(\.systemImage))
        }
        return glyphs
    }

    // MARK: - Pages

    func testAtMostFourPagesInAFixedOrder() {
        for (provider, methods) in combinations {
            let pages = ConnectionGuideContent.pages(for: provider, methods: methods)

            XCTAssertLessThanOrEqual(pages.count, ConnectionGuideContent.maximumPageCount, "\(provider)")
            XCTAssertEqual(ConnectionGuideContent.maximumPageCount, 4)
            XCTAssertEqual(pages.map(\.kind), [.howItWorks, .credentials, .openSource, .methods], "\(provider) \(methods)")
        }
    }

    func testOpenSourcePageLinksOnlyTheRepositoryAndThePrivacyPolicy() throws {
        let page = try XCTUnwrap(ConnectionGuideContent.pages(for: .apple, methods: [.apiKey]).first { $0.kind == .openSource })

        XCTAssertEqual(page.links.map(\.url), [ProjectLinks.repository, ProjectLinks.privacyPolicy])
        XCTAssertEqual(page.links.map(\.button), [.sourceCode, .privacyPolicy])
        XCTAssertEqual(ProjectLinks.repository.absoluteString, "https://github.com/r1b2ns/stack-connect")
        XCTAssertEqual(ProjectLinks.privacyPolicy.absoluteString,
                       "https://github.com/r1b2ns/stack-connect/blob/master/PRIVACY.md",
                       "the App Store privacy policy URL")
    }

    func testLastPageListsTheMethodsOnTheProvidersPath() throws {
        let choice = try XCTUnwrap(ConnectionGuideContent.pages(for: .apple, methods: [.apiKey, .appleIdSignIn]).last)
        XCTAssertEqual(choice.title, String(localized: "Choose How to Connect"))
        XCTAssertEqual(choice.items.map(\.title), [AccountConnectionMethod.apiKey.title, AccountConnectionMethod.appleIdSignIn.title])

        let single = try XCTUnwrap(ConnectionGuideContent.pages(for: .firebase, methods: [.serviceAccount]).last)
        XCTAssertEqual(single.title, String(localized: "How You'll Connect"))
        XCTAssertEqual(single.items.map(\.text), [AccountConnectionMethod.serviceAccount.summary(for: .firebase)])
    }

    // MARK: - Only the provider being connected (guideline 2.3.10)

    func testCopyNamesTheProviderBeingConnected() {
        for (provider, methods) in combinations {
            let pages = ConnectionGuideContent.pages(for: provider, methods: methods)
            XCTAssertTrue(pages[0].message.contains(provider.displayName), "\(provider)")
            XCTAssertTrue(pages[1].message.contains(provider.displayName), "\(provider)")
        }
    }

    func testAppStoreConnectAndFirebaseCopyNeverMentionsGooglePlayOrAndroid() {
        for (provider, methods) in combinations where provider != .googlePlay {
            let text = texts(ConnectionGuideContent.pages(for: provider, methods: methods)).joined(separator: "\n")

            for banned in ["Google Play", "Play Console", "Android"] {
                XCTAssertFalse(text.contains(banned), "\(provider) mentions \(banned)")
            }
        }
    }

    func testCopyNeverDescribesAnotherProvidersCredentials() {
        let applePages = ConnectionGuideContent.pages(for: .apple, methods: [.apiKey, .appleIdSignIn])
        let apple = texts(applePages).joined(separator: "\n")
        XCTAssertFalse(apple.contains("Google"), "no Google sign-in nor service account on App Store Connect's path")
        XCTAssertFalse(apple.contains("Firebase"))
        for method in [AccountConnectionMethod.googleSignIn, .serviceAccount] {
            XCTAssertFalse(apple.contains(method.title))
            XCTAssertFalse(applePages[1].notes.contains(ConnectionGuideContent.credentialNote(for: method, provider: .apple)))
        }

        let firebasePages = ConnectionGuideContent.pages(for: .firebase, methods: [.googleSignIn, .serviceAccount])
        let firebase = texts(firebasePages).joined(separator: "\n")
        XCTAssertFalse(firebase.contains("Apple"), "no API key or Apple password on Firebase's path")
        XCTAssertFalse(firebase.contains("App Store Connect"))
        XCTAssertFalse(firebase.contains(".p8"))
        for method in [AccountConnectionMethod.apiKey, .appleIdSignIn] {
            XCTAssertFalse(firebase.contains(method.title))
        }
    }

    func testMethodsOfAnotherProviderPassedByMistakeAreDropped() {
        let pages = ConnectionGuideContent.pages(for: .firebase, methods: [.apiKey, .appleIdSignIn, .serviceAccount])

        XCTAssertEqual(pages[1].notes, [ConnectionGuideContent.credentialNote(for: .serviceAccount, provider: .firebase)])
        XCTAssertEqual(pages.last?.items.count, 1)
    }

    // MARK: - No password or code talk without the email and password method

    func testWithoutEmailAndPasswordTheGuideNeverMentionsAppleIdPasswordsOrCodes() {
        let pages = ConnectionGuideContent.pages(for: .apple, methods: [.apiKey])
        let texts = texts(pages)
        let text = texts.joined(separator: "\n")

        XCTAssertEqual(pages[1].notes, [ConnectionGuideContent.credentialNote(for: .apiKey, provider: .apple)])
        XCTAssertEqual(pages.last?.items.map(\.title), [AccountConnectionMethod.apiKey.title])
        // In the language the test runs in: nothing of the email and password method.
        let emailAndPassword = ConnectionGuideContent.credentialNote(for: .appleIdSignIn, provider: .apple)
        for banned in [String(localized: "Save password on this device"),
                       String(localized: "Two-Factor Code"),
                       AccountConnectionMethod.appleIdSignIn.title,
                       AccountConnectionMethod.appleIdSignIn.summary(for: .apple),
                       emailAndPassword.text] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(banned), "mentions \"\(banned)\" while the method is off")
        }
        XCTAssertFalse(texts.contains(emailAndPassword.title ?? ""))
        // And the English source, whatever the language.
        let english = text.lowercased()
        for phrase in ["two-factor", "save password", "email and password", "apple id", "your password", "sign you in"] {
            XCTAssertFalse(english.contains(phrase), "mentions \"\(phrase)\" while the email and password method is off")
        }
    }

    func testWithEmailAndPasswordTheGuideExplainsThePassword() {
        let pages = ConnectionGuideContent.pages(for: .apple, methods: [.apiKey, .appleIdSignIn])

        XCTAssertEqual(pages[1].notes, [
            ConnectionGuideContent.credentialNote(for: .apiKey, provider: .apple),
            ConnectionGuideContent.credentialNote(for: .appleIdSignIn, provider: .apple)
        ])
        // Names the password screen's toggle exactly as it is translated.
        XCTAssertTrue(pages[1].notes[1].text.contains(String(localized: "Save password on this device")))
    }

    // MARK: - Accurate claims

    func testExportIsMentionedOnlyWhereAccountsCanBeExported() {
        XCTAssertEqual(
            ConnectionGuideContent.credentialNote(for: .apiKey, provider: .apple).text,
            String(localized: "The .p8 private key only signs short-lived tokens on this device; the key itself is never sent. It leaves this device only if you export the account yourself, in a file encrypted with a password you choose.")
        )
        XCTAssertEqual(
            ConnectionGuideContent.credentialNote(for: .serviceAccount, provider: .googlePlay).text,
            String(localized: "The service account's private key only signs short-lived tokens on this device; the key itself is never sent. It leaves this device only if you export the account yourself, in a file encrypted with a password you choose.")
        )
        XCTAssertEqual(
            ConnectionGuideContent.credentialNote(for: .serviceAccount, provider: .firebase).text,
            String(localized: "The service account's private key only signs short-lived tokens on this device; the key itself is never sent."),
            "Firebase accounts can't be exported"
        )
        XCTAssertFalse(ProviderType.firebase.supportsExport)
        XCTAssertTrue(ProviderType.apple.supportsExport)
        XCTAssertTrue(ProviderType.googlePlay.supportsExport)
    }

    func testClaimsStayConsistentWithThePrivacyLabel() {
        for (provider, methods) in combinations {
            let pages = ConnectionGuideContent.pages(for: provider, methods: methods)
            let text = texts(pages).joined(separator: "\n").lowercased()

            for overclaim in ["collects no data", "no data", "100%", "fully secure", "endorsed", "approved by apple"] {
                XCTAssertFalse(text.contains(overclaim), "\(provider): \(overclaim)")
            }
            XCTAssertFalse(text.contains("iphone"), "\(provider): say \"this device\"")
            XCTAssertNotNil(pages[1].footnote, "the analytics and crash reports the label declares are acknowledged")
        }
    }

    func testNoPrivateEndpointIsNamed() {
        for (provider, methods) in combinations {
            let text = texts(ConnectionGuideContent.pages(for: provider, methods: methods)).joined(separator: "\n")
            XCTAssertFalse(text.contains("idmsa"), "\(provider)")
            XCTAssertFalse(text.contains("iris"), "\(provider)")
        }
    }

    // MARK: - Never like "Sign in with Apple"

    func testNothingLooksLikeSignInWithApple() {
        for (provider, methods) in combinations {
            let pages = ConnectionGuideContent.pages(for: provider, methods: methods)
            XCTAssertFalse(texts(pages).contains { $0.contains("Sign in with Apple") }, "\(provider)")
            XCTAssertFalse(glyphs(pages).contains("apple.logo"), "\(provider)")
        }
        for method in AccountConnectionMethod.allCases {
            XCTAssertNotEqual(method.systemImage, "apple.logo")
            XCTAssertFalse(method.title.contains("Sign in with Apple"))
        }
        XCTAssertEqual(AccountConnectionMethod.appleIdSignIn.title, String(localized: "Sign in with email and password"))
    }

    /// Every language the app ships: the email and password wording never
    /// names Apple in a sign-in phrase, and none of the old "Sign in with
    /// Apple ID" translations is left in the renamed copy.
    func testNoLanguageReadsAsSignInWithApple() throws {
        let oldWording = [
            "Sign in with Apple", "Mit Apple-ID anmelden", "Iniciar sesión con el Apple ID",
            "Se connecter avec l'Identifiant Apple", "Accedi con Apple ID", "Apple ID でサインイン",
            "Apple ID로 로그인", "Inloggen met Apple ID", "Fazer login com o Apple ID",
            "Iniciar sessão com o ID Apple", "Войти с Apple ID", "Logga in med Apple-ID", "使用 Apple ID 登入"
        ]
        let renamed = [
            "Sign in with email and password",
            "Sign in to App Store Connect",
            "Accounts added with email and password can't be exported: the session is your personal Apple ID login. Share an App Store Connect API key instead.",
            "Renaming or deleting an identifier needs an App Store Connect API key. Accounts added with email and password can't do it: use developer.apple.com instead.",
            "Use the email and password of your Apple ID, plus its two-factor code, then pick the teams to add. If you choose to, your password is saved only in this device's Keychain. Analytics Reports need an API key."
        ]
        var checkedLanguages = 0
        for language in Bundle.main.localizations where language != "Base" {
            guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
                  let table = NSDictionary(contentsOfFile: path) as? [String: String] else { continue }
            checkedLanguages += 1
            for key in renamed {
                let value = try XCTUnwrap(table[key], "\(language) has no translation of \(key)")
                for old in oldWording {
                    XCTAssertFalse(value.contains(old), "\(language): \(value)")
                }
            }
            let methodTitle = try XCTUnwrap(table["Sign in with email and password"])
            XCTAssertFalse(methodTitle.contains("Apple"), "\(language): \(methodTitle)")
            XCTAssertFalse(try XCTUnwrap(table["Sign in to App Store Connect"]).contains("Apple"), language)
            XCTAssertNil(table["Sign in with Apple ID"], "\(language): the old key is gone")
        }
        XCTAssertEqual(checkedLanguages, 14, "every language of the catalog, English included")
    }

    // MARK: - Methods

    func testAvailableMethodsPerProvider() {
        XCTAssertEqual(AccountConnectionMethod.available(for: .apple, appleIdSignIn: true, googleSignIn: true), [.apiKey, .appleIdSignIn])
        XCTAssertEqual(AccountConnectionMethod.available(for: .apple, appleIdSignIn: false, googleSignIn: true), [.apiKey])
        XCTAssertEqual(AccountConnectionMethod.available(for: .firebase, appleIdSignIn: true, googleSignIn: true), [.googleSignIn, .serviceAccount])
        XCTAssertEqual(AccountConnectionMethod.available(for: .googlePlay, appleIdSignIn: true, googleSignIn: false), [.serviceAccount])
    }

    func testEveryChooserCardHasItsOwnAnalyticsButton() {
        let buttons = AccountConnectionMethod.allCases.map(AnalyticsButton.connectionMethodButton(for:))

        XCTAssertEqual(buttons, [.useApiKey, .useAppleIdSignIn, .useGoogleSignIn, .useServiceAccount])
        XCTAssertEqual(Set(buttons.map(\.rawValue)).count, buttons.count)
    }

    func testSourceFileLinksPointAtMaster() {
        XCTAssertEqual(
            ProjectLinks.applePasswordKeychainStore.absoluteString,
            "https://github.com/r1b2ns/stack-connect/blob/master/StackConnect/Infra/AppleSession/ApplePasswordKeychainStore.swift"
        )
    }
}
