import Foundation

/// The project's public pages the app links to: the open-source repository,
/// the privacy policy (the same URL as the App Store privacy policy) and
/// individual source files, so users can check what the app says about their
/// credentials against the code.
///
/// Only files that exist in the repository are linked. A source file link
/// points at `master`, so a file added on a feature branch resolves once that
/// branch is merged.
enum ProjectLinks {

    // Constant, well-formed URLs: the force unwraps cannot fail.

    /// The open-source repository on GitHub.
    static let repository = URL(string: "https://github.com/r1b2ns/stack-connect")!

    /// `PRIVACY.md` on GitHub: the privacy policy linked from the App Store.
    static let privacyPolicy = URL(string: "https://github.com/r1b2ns/stack-connect/blob/master/PRIVACY.md")!

    /// Where the saved Apple ID password lives (`ApplePasswordKeychainStore`).
    static let applePasswordKeychainStore = sourceFile("StackConnect/Infra/AppleSession/ApplePasswordKeychainStore.swift")

    /// A file of the repository, by its path from the repository root.
    static func sourceFile(_ path: String) -> URL {
        repository.appending(path: "blob/master").appending(path: path)
    }
}

// MARK: - Link items

extension StackExternalLinkItem {

    /// The open-source repository on GitHub.
    static var sourceCode: StackExternalLinkItem {
        StackExternalLinkItem(
            title: String(localized: "Source Code on GitHub",
                          comment: "Link to the app's open-source repository on GitHub."),
            systemImage: "chevron.left.forwardslash.chevron.right",
            url: ProjectLinks.repository,
            button: .sourceCode
        )
    }

    /// StackConnect's privacy policy (`PRIVACY.md`).
    static var privacyPolicy: StackExternalLinkItem {
        StackExternalLinkItem(
            title: String(localized: "Privacy Policy"),
            systemImage: "hand.raised.fill",
            url: ProjectLinks.privacyPolicy,
            button: .privacyPolicy
        )
    }

    /// Where the saved Apple ID password lives in the code. The title is the
    /// file name, as on GitHub (not translated).
    static var applePasswordKeychainStore: StackExternalLinkItem {
        StackExternalLinkItem(
            title: "ApplePasswordKeychainStore.swift",
            systemImage: "doc.text",
            url: ProjectLinks.applePasswordKeychainStore,
            button: .sourceFile
        )
    }
}
