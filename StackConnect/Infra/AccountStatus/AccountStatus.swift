import Combine
import Foundation

// MARK: - Model

/// A problem with an account the app already knows about locally (no network
/// call), shown as a chip in the accounts and apps lists.
enum AccountStatusIssue: Int, Comparable, CaseIterable, Sendable {
    // Disconnected: the account can't reach its store until the user acts.

    /// The personal sign-in expired: an Apple ID session App Store Connect
    /// refused, or a Google login Google stopped accepting (see
    /// `ExpiredSignInResolver`).
    case signInExpired
    /// An imported account whose shared file expired (`AccountModel.isExpired`).
    case accessExpired
    /// The account's credentials are missing from this device's Keychain.
    case missingCredentials

    // Needs attention: the account still works, but something waits on the user.

    /// App Store Connect agreements waiting to be accepted
    /// (`AccountModel.hasPendingAgreements`, set by the sync).
    case pendingAgreements
    /// An imported account whose shared file expires within 24 hours
    /// (`AccountModel.isExpiringSoon`).
    case accessExpiringSoon

    var level: AccountStatus.Level {
        switch self {
        case .signInExpired, .accessExpired, .missingCredentials:
            return .disconnected
        case .pendingAgreements, .accessExpiringSoon:
            return .needsAttention
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What is wrong with an account, for display. Accounts without any issue have
/// no status (`nil`), so the lists show no chip for them.
struct AccountStatus: Equatable, Sendable {

    enum Level: Equatable, Sendable {
        /// The account can't sync: its login or credentials are unusable.
        case disconnected
        /// The account syncs, but something is pending on the user's side.
        case needsAttention
    }

    /// Never empty, most important first (disconnected issues lead).
    let issues: [AccountStatusIssue]

    /// `nil` when `issues` is empty.
    init?(issues: some Sequence<AccountStatusIssue>) {
        let sorted = Array(Set(issues)).sorted()
        guard !sorted.isEmpty else { return nil }
        self.issues = sorted
    }

    var level: Level {
        issues.contains { $0.level == .disconnected } ? .disconnected : .needsAttention
    }
}

// MARK: - Resolver

/// Tells which accounts have a problem, from local data only.
@MainActor
protocol AccountStatusResolving {
    /// Statuses keyed by account id; accounts without issues are left out.
    func statuses(for accounts: [AccountModel]) -> [String: AccountStatus]
}

extension AccountStatusResolving {
    func status(for account: AccountModel) -> AccountStatus? {
        statuses(for: [account])[account.id]
    }
}

/// `AccountStatusResolving` over what the app already tracks:
/// - expired sign-ins (`ExpiredSignInResolving`: Apple ID session, Google login);
/// - the Keychain credentials (`credentials.{accountId}`);
/// - the account record (`isExpired`, `isExpiringSoon`, `hasPendingAgreements`).
///
/// Google sensitive scopes not granted yet (Remote Config, Analytics) are not
/// an issue: they are asked for only when the user opens those screens, so an
/// account without them is working as intended.
@MainActor
struct AccountStatusResolver: AccountStatusResolving {

    private let keychain: KeyStorable
    private let signInExpiry: ExpiredSignInResolving

    init(keychain: KeyStorable, signInExpiry: ExpiredSignInResolving? = nil) {
        self.keychain = keychain
        self.signInExpiry = signInExpiry ?? ExpiredSignInResolver(keychain: keychain)
    }

    func statuses(for accounts: [AccountModel]) -> [String: AccountStatus] {
        let expiredSignInIds = Set(signInExpiry.expiredSignIns(in: accounts).flatMap { $0.accounts.map(\.id) })

        var result: [String: AccountStatus] = [:]
        for account in accounts {
            var issues: [AccountStatusIssue] = []
            if expiredSignInIds.contains(account.id) {
                issues.append(.signInExpired)
            }
            if account.isExpired {
                issues.append(.accessExpired)
            } else if account.isExpiringSoon {
                issues.append(.accessExpiringSoon)
            }
            if keychain.data(forKey: "credentials.\(account.id)") == nil {
                issues.append(.missingCredentials)
            }
            if account.providerType == .apple, account.hasPendingAgreements {
                issues.append(.pendingAgreements)
            }
            if let status = AccountStatus(issues: issues) {
                result[account.id] = status
            }
        }
        return result
    }
}

// MARK: - Service

/// Account statuses for screens that only know an account id (the apps lists),
/// plus a signal to recompute them.
@MainActor
protocol AccountStatusProviding: AnyObject {
    /// Emits on the main queue when a status may have changed: a sign-in
    /// expired or works again (`.signInStatusDidChange`), or a sync finished
    /// (it may flag or clear pending agreements).
    var changes: AnyPublisher<Void, Never> { get }
    /// Statuses of `accounts`, keyed by account id (see `AccountStatusResolving`).
    func statuses(for accounts: [AccountModel]) -> [String: AccountStatus]
    /// The freshest stored record of the account, resolved; `nil` when it has
    /// no issue or can't be read.
    func status(forAccountId accountId: String) async -> AccountStatus?
}

/// `AccountStatusProviding` over storage and an `AccountStatusResolving`.
@MainActor
final class AccountStatusService: AccountStatusProviding {

    let changes: AnyPublisher<Void, Never>

    /// Read only by `status(forAccountId:)`; `nil` ⇒ `SwiftDataStorable.shared`,
    /// resolved on first use.
    private let storageOverride: PersistentStorable?
    private let resolver: AccountStatusResolving

    /// - Parameters:
    ///   - storage: where `status(forAccountId:)` reads the account (default:
    ///     `SwiftDataStorable.shared`).
    ///   - syncFinished: emits after each finished sync (default:
    ///     `SyncService.shared` timestamps).
    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable,
        resolver: AccountStatusResolving? = nil,
        notificationCenter: NotificationCenter = .default,
        syncFinished: AnyPublisher<Void, Never>? = nil
    ) {
        self.storageOverride = storage
        self.resolver = resolver ?? AccountStatusResolver(keychain: keychain)
        let signIn = notificationCenter.publisher(for: .signInStatusDidChange).map { _ in () }
        self.changes = signIn
            .merge(with: syncFinished ?? Self.syncFinished)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func statuses(for accounts: [AccountModel]) -> [String: AccountStatus] {
        resolver.statuses(for: accounts)
    }

    func status(forAccountId accountId: String) async -> AccountStatus? {
        let storage: PersistentStorable = storageOverride ?? SwiftDataStorable.shared
        guard let account = (try? await storage.fetch(AccountModel.self, id: accountId)) ?? nil else { return nil }
        return resolver.status(for: account)
    }

    private static var syncFinished: AnyPublisher<Void, Never> {
        SyncService.shared.$state
            .map(\.lastSyncedAt)
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}
