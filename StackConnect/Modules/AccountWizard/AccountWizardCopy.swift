import Foundation

/// The wizard's copy, in one place. App Review rules (keep them when
/// editing): a store is only named on its own path, the email and password
/// method never reads as "Sign in with Apple", and no method is promoted
/// over another ("Recommended").
enum AccountWizardCopy {

    // MARK: - Header

    static func headerTitle(for state: AccountWizardUiState) -> String {
        if state.entry.isReconnect {
            return String(localized: "Reconnect Account", comment: "Account wizard: navigation title while reconnecting an account.")
        }
        guard let kind = state.kind?.kind, state.step != .type else {
            return String(localized: "Add Account")
        }
        return title(of: kind)
    }

    /// "Step 2 of 4 · Credentials".
    static func stepLabel(for state: AccountWizardUiState) -> String {
        let short = shortTitle(of: state.step, state: state)
        return String(localized: "Step \(state.stepIndex + 1) of \(state.stepCount) · \(short)",
                      comment: "Account wizard: above the step title. Arguments: the step number, the number of steps, the step's short name.")
    }

    static func shortTitle(of step: AccountWizardStep, state: AccountWizardUiState) -> String {
        switch step {
        case .type:
            return String(localized: "Type", comment: "Account wizard: short name of the account type step.")
        case .method:
            return String(localized: "Method", comment: "Account wizard: short name of the connection method step.")
        case .credentials:
            return state.method?.authStyle == .webSignIn
                ? String(localized: "Sign In", comment: "Account wizard: short name of the web sign-in step.")
                : String(localized: "Credentials", comment: "Account wizard: short name of the credentials step.")
        case .code:
            return String(localized: "Code", comment: "Account wizard: short name of the verification code step.")
        case .items:
            switch state.kind?.selection?.kind {
            case .team?:     return String(localized: "Teams", comment: "Account wizard: short name of the team selection step.")
            case .apps?:     return String(localized: "Apps")
            case .projects?: return String(localized: "Projects")
            case nil:        return ""
            }
        case .review:
            return String(localized: "Review", comment: "Account wizard: short name of the last step.")
        }
    }

    // MARK: - Step titles

    static func title(for state: AccountWizardUiState) -> String {
        switch state.step {
        case .type:
            return String(localized: "What account do you want to connect?", comment: "Account wizard: title of the account type step.")
        case .method:
            return String(localized: "How do you want to connect?", comment: "Account wizard: title of the connection method step.")
        case .credentials:
            if state.entry.isReconnect {
                return state.method == .scexportFile
                    ? String(localized: "Import Again", comment: "Account wizard: title when re-importing the file of an expired shared account.")
                    : String(localized: "Sign In Again", comment: "Account wizard: title when reconnecting a personal sign-in.")
            }
            switch state.method {
            case .apiKey?:         return String(localized: "API Key Details", comment: "Account wizard: credentials step title of the App Store Connect API key.")
            case .appleIdSignIn?:  return String(localized: "Sign in to App Store Connect",
                                                 comment: "Title of the App Store Connect email and password screen. Must not read as Apple's \"Sign in with Apple\".")
            case .googleSignIn?:   return String(localized: "Sign In with Your Google Account", comment: "Account wizard: credentials step title of the Google sign-in.")
            case .serviceAccount?: return String(localized: "Service Account Key", comment: "Account wizard: credentials step title of a Google service account JSON key.")
            case .scexportFile?:   return String(localized: "File and Password", comment: "Account wizard: credentials step title of an import.")
            case nil:              return ""
            }
        case .code:
            return String(localized: "Verification Code", comment: "Account wizard: title of the two-factor code step.")
        case .items:
            switch state.kind?.selection?.kind {
            case .team?:     return String(localized: "Choose Teams")
            case .apps?:     return String(localized: "Choose the Apps", comment: "Account wizard: title of the Google Play app selection step.")
            case .projects?: return String(localized: "Choose the Projects", comment: "Account wizard: title of the Firebase project selection step.")
            case nil:        return ""
            }
        case .review:
            return String(localized: "Review and Name", comment: "Account wizard: title of the review step.")
        }
    }

    static func caption(for state: AccountWizardUiState) -> String? {
        switch state.step {
        case .type:
            return String(localized: "The next steps adjust to the type you choose.", comment: "Account wizard: caption of the account type step.")
        case .method:
            return String(localized: "Choose one. You can add the other one later.", comment: "Account wizard: caption of the connection method step.")
        case .credentials:
            if let account = state.reconnectAccount {
                let name = account.name
                switch state.method {
                case .appleIdSignIn?:
                    return String(localized: "The session of “\(name)” expired. Use the same Apple ID.",
                                  comment: "Account wizard: reconnecting an email and password account. The placeholder is the account name.")
                case .googleSignIn?:
                    return String(localized: "The sign-in of “\(name)” expired. Sign in with the same Google account.",
                                  comment: "Account wizard: reconnecting a Google account. The placeholder is the account name.")
                default:
                    return String(localized: "“\(name)” expired. Import a new file of this account and its password.",
                                  comment: "Account wizard: re-importing an expired shared account. The placeholder is the account name.")
                }
            }
            switch state.method {
            case .apiKey?:
                return String(localized: "In App Store Connect › Users and Access › Integrations › App Store Connect API.",
                              comment: "Account wizard: where the API key is created.")
            case .appleIdSignIn?:
                return String(localized: "Use the email and password of the Apple ID you use in App Store Connect.",
                              comment: "Account wizard: caption of the email and password step.")
            case .googleSignIn?:
                return String(localized: "You sign in on Google's page and come back here.", comment: "Account wizard: caption of the Google sign-in step.")
            case .serviceAccount?:
                return state.kind?.kind == .provider(.googlePlay)
                    ? String(localized: "Do this once in Google Cloud and Play Console. Access can take a few hours to apply.",
                             comment: "Account wizard: caption of the Google Play service account step.")
                    : String(localized: "In the Firebase console: Project settings › Service accounts › Generate new private key.",
                             comment: "Account wizard: caption of the Firebase service account step.")
            case .scexportFile?:
                return String(localized: ".scexport files are encrypted with the password set when exporting.",
                              comment: "Account wizard: caption of the import step.")
            case nil:
                return nil
            }
        case .code:
            return String(localized: "Enter the code Apple sent to your devices or phone.", comment: "Account wizard: caption of the two-factor code step.")
        case .items:
            switch state.kind?.selection?.kind {
            case .team?:     return String(localized: "This Apple ID belongs to these App Store Connect teams.", comment: "Account wizard: caption of the team selection step.")
            case .apps?:     return String(localized: "Apps this account can access in Play Console.", comment: "Account wizard: caption of the Google Play app selection step.")
            case .projects?: return String(localized: "Projects this account can access.", comment: "Account wizard: caption of the Firebase project selection step.")
            case nil:        return nil
            }
        case .review:
            return String(localized: "The name only appears in StackConnect, so you can recognize the account.", comment: "Account wizard: caption of the review step.")
        }
    }

    // MARK: - Kinds

    static func title(of kind: AccountWizardKind) -> String {
        switch kind {
        case .provider(let provider): return provider.displayName
        case .importFile:             return String(localized: "Import File", comment: "Account wizard: the import kind of the Type step.")
        }
    }

    static func subtitle(of kind: AccountWizardKind) -> String {
        switch kind {
        case .provider(.apple):
            return String(localized: "Apps, builds, TestFlight and reviews", comment: "Account wizard: what an App Store Connect account gives.")
        case .provider(.googlePlay):
            return String(localized: "Apps, releases, reviews and users", comment: "Account wizard: what a Google Play account gives.")
        case .provider(.firebase):
            return String(localized: "Projects, Remote Config and Messaging", comment: "Account wizard: what a Firebase account gives.")
        case .importFile:
            return String(localized: "An account exported from another device (.scexport)", comment: "Account wizard: the import kind of the Type step.")
        }
    }

    /// "API key or email and password".
    static func methodsLabel(of kind: AccountWizardKindConfig) -> String {
        kind.methods.map(label(of:)).formatted(.list(type: .or))
    }

    static func systemImage(of kind: AccountWizardKind) -> String {
        switch kind {
        case .provider(let provider): return provider.iconName
        case .importFile:             return "square.and.arrow.down"
        }
    }

    // MARK: - Methods

    /// The short name of a method (Type rows, the Review summary).
    static func label(of method: AccountWizardMethod) -> String {
        switch method {
        case .apiKey:         return String(localized: "API key", comment: "Account wizard: short name of the API key method.")
        case .appleIdSignIn:  return String(localized: "Email and password", comment: "Account wizard: short name of the App Store Connect email and password method.")
        case .googleSignIn:   return String(localized: "Google account", comment: "Account wizard: short name of the Google sign-in method.")
        case .serviceAccount: return String(localized: "Service account", comment: "Account wizard: short name of the service account method.")
        case .scexportFile:   return String(localized: ".scexport file", comment: "Account wizard: short name of the import method.")
        }
    }

    /// Review: where the credentials are kept.
    static func storage(of method: AccountWizardMethod, savesPassword: Bool) -> String {
        switch method {
        case .apiKey, .serviceAccount, .scexportFile:
            return String(localized: "The key, in this device's Keychain", comment: "Account wizard review: where a key file is stored.")
        case .googleSignIn:
            return String(localized: "The sign-in, in this device's Keychain", comment: "Account wizard review: where a Google login is stored.")
        case .appleIdSignIn:
            return savesPassword
                ? String(localized: "The session and the password, in this device's Keychain", comment: "Account wizard review: email and password with Save password on.")
                : String(localized: "Only the session, in this device's Keychain", comment: "Account wizard review: email and password with Save password off.")
        }
    }

    // MARK: - Done

    static func doneTitle(for result: AccountWizardResult) -> String {
        if result.isReconnect {
            return String(localized: "Account Reconnected", comment: "Account wizard done screen: an account works again.")
        }
        return result.names.count > 1
            ? String(localized: "\(result.names.count) Accounts Connected", comment: "Account wizard done screen: several accounts added.")
            : String(localized: "Account Connected", comment: "Account wizard done screen: one account added.")
    }

    static func doneMessage(for result: AccountWizardResult) -> String {
        if result.isReconnect {
            return String(localized: "It syncs again now.", comment: "Account wizard done screen: after reconnecting.")
        }
        let store = result.provider?.displayName ?? ""
        return result.names.count > 1
            ? String(localized: "They're already in the \(store) group of your accounts list.", comment: "Account wizard done screen. The placeholder is the store, e.g. Firebase.")
            : String(localized: "It's already in the \(store) group of your accounts list.", comment: "Account wizard done screen. The placeholder is the store, e.g. Firebase.")
    }
}
