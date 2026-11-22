import XCTest
@testable import StackConnect

/// The sign-in status stores read by the Home "sign in again" banner: the
/// Google login store, and `.signInStatusDidChange` from both stores.
@MainActor
final class SignInStatusStoreTests: XCTestCase {

    private let suiteName = "SignInStatusStoreTests.\(UUID().uuidString)"
    private lazy var defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard
    private var center: NotificationCenter!
    private var changes = 0
    private var observer: NSObjectProtocol?

    override func setUp() async throws {
        try await super.setUp()
        center = NotificationCenter()
        changes = 0
        observer = center.addObserver(forName: .signInStatusDidChange, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.changes += 1 }
        }
    }

    override func tearDown() async throws {
        if let observer { center.removeObserver(observer) }
        observer = nil
        center = nil
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    // MARK: - Google

    func testGoogleLoginExpiryIsRememberedAndPostedOnce() {
        let store = GoogleLoginStatusStore(defaults: defaults, center: center)

        store.markExpired(loginId: "user-1")
        store.markExpired(loginId: "user-1")

        XCTAssertTrue(store.isExpired(loginId: "user-1"))
        XCTAssertFalse(store.isExpired(loginId: "user-2"))
        XCTAssertEqual(changes, 1, "only the first expiry is a change")
        XCTAssertTrue(GoogleLoginStatusStore(defaults: defaults, center: center).isExpired(loginId: "user-1"), "survives a relaunch")
    }

    func testGoogleLoginWorkingAgainIsPostedOnlyWhenItWasExpired() {
        let store = GoogleLoginStatusStore(defaults: defaults, center: center)

        store.markValid(loginId: "user-1")
        XCTAssertEqual(changes, 0)

        store.markExpired(loginId: "user-1")
        store.markValid(loginId: "user-1")

        XCTAssertFalse(store.isExpired(loginId: "user-1"))
        XCTAssertEqual(changes, 2)
    }

    // MARK: - Apple

    func testAppleSessionPostsAChangeOnANewExpiryAndOnRecovery() {
        let store = AppleSessionStatusStore(defaults: defaults, center: center)

        store.markExpired(appleId: "dev@example.com")
        store.markExpired(appleId: "dev@example.com")
        XCTAssertEqual(changes, 1, "a repeated refusal isn't a change")

        store.markValid(appleId: "dev@example.com")
        store.markValid(appleId: "dev@example.com")
        XCTAssertEqual(changes, 2, "only the recovery of an expired session is a change")
    }
}
