import Foundation

/// The single policy deciding which stores the UI may show (App Review
/// guideline 2.3.10): Google Play is shown only while
/// `FeatureFlag.googlePlayAccounts` is ON. App Store Connect and Firebase are
/// always available.
///
/// Every Google Play surface asks this policy instead of reading the flag
/// directly, so turning the flag back ON restores all of them at once. Hidden
/// accounts stay in storage untouched: the policy only filters what is shown,
/// synced, imported or seeded.
///
/// The remote part of the flag is frozen at launch, so these answers do not
/// change during a session.
extension FeatureFlags {

    /// Whether `provider` may appear anywhere in the UI.
    func isProviderAvailable(_ provider: ProviderType) -> Bool {
        switch provider {
        case .apple, .firebase: return true
        case .googlePlay:       return isEnabled(.googlePlayAccounts)
        }
    }

    /// `ProviderType.allCases` (in that order) narrowed to the available stores.
    var availableProviders: [ProviderType] {
        ProviderType.allCases.filter(isProviderAvailable)
    }

    /// Whether `account` may be shown (its store is available).
    func isVisible(_ account: AccountModel) -> Bool {
        isProviderAvailable(account.providerType)
    }

    /// `accounts` without those of unavailable stores, order preserved.
    func visibleAccounts(_ accounts: [AccountModel]) -> [AccountModel] {
        accounts.filter(isVisible)
    }
}
