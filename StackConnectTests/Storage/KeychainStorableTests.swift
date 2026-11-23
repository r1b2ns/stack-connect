import Security
import UIKit
import XCTest
@testable import StackConnect

final class KeychainStorableTests: XCTestCase {

    private let afterFirstUnlock = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    private let whenUnlocked = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    private let credentialsKey = "credentials.account-1"
    private let passwordKey = ApplePasswordKeychainStore.itemKey(appleId: "dev@example.com")

    private var backend: FakeKeychainBackend!
    private var sut: KeychainStorable!

    override func setUp() {
        super.setUp()
        backend = FakeKeychainBackend()
        sut = KeychainStorable(service: "test.service", backend: backend)
    }

    override func tearDown() {
        sut = nil
        backend = nil
        super.tearDown()
    }

    private func data(_ string: String) -> Data { Data(string.utf8) }

    // MARK: - Policy

    func testStandardPolicyKeepsTheApplePasswordWhenUnlockedAndEverythingElseAfterFirstUnlock() {
        let policy = KeychainAccessibilityPolicy.standard
        XCTAssertEqual(policy.accessibility(forKey: passwordKey), .whenUnlockedThisDeviceOnly)
        XCTAssertEqual(policy.accessibility(forKey: credentialsKey), .afterFirstUnlockThisDeviceOnly)
        XCTAssertEqual(policy.accessibility(forKey: AppleSessionKeychainStore.itemKey(appleId: "dev@example.com")),
                       .afterFirstUnlockThisDeviceOnly)
        XCTAssertEqual(policy.accessibility(forKey: "googleLogin.grant"), .afterFirstUnlockThisDeviceOnly)
    }

    func testPasswordKeyIsWrittenWhenUnlockedWhileOthersAreWrittenAfterFirstUnlock() {
        sut.set("secret", forKey: passwordKey)
        sut.set(data("p8"), forKey: credentialsKey)

        XCTAssertEqual(backend.items[passwordKey]?.accessibility, whenUnlocked)
        XCTAssertEqual(backend.items[credentialsKey]?.accessibility, afterFirstUnlock)
    }

    func testApplePasswordStoreWritesThroughTheStricterClass() {
        let store = ApplePasswordKeychainStore(keychain: sut)
        store.save("secret", for: "Dev@Example.com ")

        XCTAssertEqual(backend.items[passwordKey]?.accessibility, whenUnlocked)
        XCTAssertEqual(store.password(for: "dev@example.com"), "secret")
    }

    // MARK: - Update then add

    func testNewItemIsUpdatedFirstThenAdded() {
        sut.set(data("v1"), forKey: credentialsKey)

        XCTAssertEqual(backend.calls, [
            .update(key: credentialsKey, setsData: true, accessibility: afterFirstUnlock),
            .add(key: credentialsKey)
        ])
        XCTAssertEqual(backend.items[credentialsKey]?.data, data("v1"))
    }

    func testExistingItemIsUpdatedInPlaceWithItsAccessibility() {
        backend.items[credentialsKey] = .init(data: data("old"), accessibility: whenUnlocked)

        sut.set(data("new"), forKey: credentialsKey)

        XCTAssertEqual(backend.calls, [.update(key: credentialsKey, setsData: true, accessibility: afterFirstUnlock)])
        XCTAssertEqual(backend.items[credentialsKey], .init(data: data("new"), accessibility: afterFirstUnlock))
        XCTAssertFalse(sut.hasPendingOperations)
    }

    // MARK: - Locked device

    func testInteractionNotAllowedNeverFallsThroughToAdd() {
        backend.items[credentialsKey] = .init(data: data("old"), accessibility: whenUnlocked)
        backend.isLocked = true

        sut.set(data("new"), forKey: credentialsKey)

        XCTAssertEqual(backend.calls, [.update(key: credentialsKey, setsData: true, accessibility: afterFirstUnlock)])
        XCTAssertEqual(backend.items[credentialsKey]?.data, data("old"))
        XCTAssertEqual(sut.pendingOperation(forKey: credentialsKey), .write(data("new")))
    }

    func testPendingValueIsReadableAndPresentInThisProcess() {
        backend.items[credentialsKey] = .init(data: data("old"), accessibility: whenUnlocked)
        backend.isLocked = true

        sut.set("new", forKey: credentialsKey)

        XCTAssertEqual(sut.string(forKey: credentialsKey), "new")
        XCTAssertEqual(sut.presence(forKey: credentialsKey), .present)
    }

    func testLatestPendingValueWins() {
        backend.items[credentialsKey] = .init(data: data("old"), accessibility: whenUnlocked)
        backend.isLocked = true

        sut.set("first", forKey: credentialsKey)
        sut.set("second", forKey: credentialsKey)
        backend.isLocked = false
        sut.flushPendingWrites()

        XCTAssertEqual(backend.items[credentialsKey], .init(data: data("second"), accessibility: afterFirstUnlock))
    }

    func testFlushOnUnlockWritesThePendingValue() {
        backend.items[credentialsKey] = .init(data: data("old"), accessibility: whenUnlocked)
        backend.isLocked = true
        sut.set("new", forKey: credentialsKey)

        XCTAssertEqual(sut.flushPendingWrites(), 1, "Still locked: stays queued")

        backend.isLocked = false
        XCTAssertEqual(sut.flushPendingWrites(), 0)
        XCTAssertFalse(sut.hasPendingOperations)
        XCTAssertEqual(backend.items[credentialsKey], .init(data: data("new"), accessibility: afterFirstUnlock))
        XCTAssertEqual(sut.string(forKey: credentialsKey), "new")
    }

    func testPasswordAddedWhileLockedIsDeferredAndFlushed() {
        backend.isLocked = true

        sut.set("secret", forKey: passwordKey)

        XCTAssertNil(backend.items[passwordKey])
        XCTAssertEqual(sut.string(forKey: passwordKey), "secret")

        backend.isLocked = false
        sut.flushPendingWrites()
        XCTAssertEqual(backend.items[passwordKey], .init(data: data("secret"), accessibility: whenUnlocked))
    }

    func testAfterFirstUnlockItemIsWrittenWhileLocked() {
        backend.items[credentialsKey] = .init(data: data("old"), accessibility: afterFirstUnlock)
        backend.isLocked = true

        sut.set("new", forKey: credentialsKey)

        XCTAssertFalse(sut.hasPendingOperations)
        XCTAssertEqual(backend.items[credentialsKey]?.data, data("new"))
    }

    func testDeleteCancelsPendingWrite() {
        backend.items[credentialsKey] = .init(data: data("old"), accessibility: afterFirstUnlock)
        backend.forcedUpdateStatusByKey[credentialsKey] = errSecInteractionNotAllowed
        sut.set("new", forKey: credentialsKey)
        XCTAssertEqual(sut.pendingOperation(forKey: credentialsKey), .write(data("new")))

        sut.removeObject(forKey: credentialsKey)

        XCTAssertNil(sut.pendingOperation(forKey: credentialsKey))
        XCTAssertNil(backend.items[credentialsKey])
        XCTAssertNil(sut.data(forKey: credentialsKey))
        XCTAssertEqual(sut.presence(forKey: credentialsKey), .missing)
    }

    func testDeleteRefusedWhileLockedIsQueuedAndHidesTheItem() {
        backend.items[credentialsKey] = .init(data: data("old"), accessibility: whenUnlocked)
        backend.isLocked = true
        sut.set("new", forKey: credentialsKey)

        sut.removeObject(forKey: credentialsKey)

        XCTAssertEqual(sut.pendingOperation(forKey: credentialsKey), .delete)
        XCTAssertNil(sut.data(forKey: credentialsKey))
        XCTAssertEqual(sut.presence(forKey: credentialsKey), .missing)

        backend.isLocked = false
        sut.flushPendingWrites()
        XCTAssertNil(backend.items[credentialsKey])
        XCTAssertFalse(sut.hasPendingOperations)
    }

    func testOtherWriteFailureIsNotQueued() {
        backend.items[credentialsKey] = .init(data: data("old"), accessibility: afterFirstUnlock)
        backend.forcedUpdateStatusByKey[credentialsKey] = errSecAuthFailed

        sut.set("new", forKey: credentialsKey)

        XCTAssertFalse(sut.hasPendingOperations)
        XCTAssertFalse(backend.calls.contains(.add(key: credentialsKey)))
    }

    func testLockedReadOfUnmigratedItemIsUnavailable() {
        backend.items[credentialsKey] = .init(data: data("old"), accessibility: whenUnlocked)
        backend.isLocked = true

        XCTAssertNil(sut.data(forKey: credentialsKey))
        XCTAssertEqual(sut.presence(forKey: credentialsKey), .unavailable)
    }

    func testConcurrentWritesAreSafe() {
        let keychain: KeychainStorable = sut
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            keychain.set("value-\(index)", forKey: "key.\(index % 10)")
            _ = keychain.string(forKey: "key.\(index % 10)")
        }
        XCTAssertEqual(backend.items.count, 10)
    }
}

// MARK: - Migration

final class KeychainAccessibilityMigrationTests: XCTestCase {

    private let afterFirstUnlock = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    private let whenUnlocked = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    private let passwordKey = ApplePasswordKeychainStore.itemKey(appleId: "dev@example.com")
    private let sessionKey = AppleSessionKeychainStore.itemKey(appleId: "dev@example.com")
    private let credentialsKey = "credentials.account-1"

    private var backend: FakeKeychainBackend!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        backend = FakeKeychainBackend()
        suiteName = "KeychainAccessibilityMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        backend = nil
        super.tearDown()
    }

    private func makeSUT() -> KeychainAccessibilityMigration {
        KeychainAccessibilityMigration(service: "test.service", policy: .standard, backend: backend, defaults: defaults)
    }

    private func seedLegacyItems() {
        for key in [credentialsKey, sessionKey, passwordKey] {
            backend.items[key] = .init(data: Data(key.utf8), accessibility: whenUnlocked)
        }
    }

    func testMigratesOnlyNonPasswordItemsAndKeepsTheirData() {
        seedLegacyItems()

        XCTAssertEqual(makeSUT().runIfNeeded(), .completed(migrated: 2))

        XCTAssertEqual(backend.items[credentialsKey], .init(data: Data(credentialsKey.utf8), accessibility: afterFirstUnlock))
        XCTAssertEqual(backend.items[sessionKey], .init(data: Data(sessionKey.utf8), accessibility: afterFirstUnlock))
        XCTAssertEqual(backend.items[passwordKey], .init(data: Data(passwordKey.utf8), accessibility: whenUnlocked))
        XCTAssertFalse(backend.calls.contains { if case .update(_, true, _) = $0 { return true } else { return false } },
                       "Must never write item data")
        XCTAssertFalse(backend.calls.contains(.update(key: passwordKey, setsData: false, accessibility: afterFirstUnlock)))
        XCTAssertTrue(defaults.bool(forKey: KeychainAccessibilityMigration.completedDefaultsKey))
    }

    func testIsIdempotent() {
        seedLegacyItems()
        let sut = makeSUT()
        sut.runIfNeeded()
        backend.resetCalls()

        XCTAssertEqual(sut.runIfNeeded(), .alreadyCompleted)
        XCTAssertTrue(backend.calls.isEmpty)

        // Even without the flag, items already in their class are skipped.
        defaults.removeObject(forKey: KeychainAccessibilityMigration.completedDefaultsKey)
        XCTAssertEqual(sut.runIfNeeded(), .completed(migrated: 0))
        XCTAssertFalse(backend.calls.contains { if case .update = $0 { return true } else { return false } })
    }

    func testEmptyKeychainCompletes() {
        XCTAssertEqual(makeSUT().runIfNeeded(), .completed(migrated: 0))
        XCTAssertTrue(defaults.bool(forKey: KeychainAccessibilityMigration.completedDefaultsKey))
    }

    func testUpdateFailureIsNotRecordedAndRetriesNextTime() {
        seedLegacyItems()
        backend.forcedUpdateStatusByKey[sessionKey] = errSecInteractionNotAllowed
        let sut = makeSUT()

        XCTAssertEqual(sut.runIfNeeded(), .failed)
        XCTAssertFalse(defaults.bool(forKey: KeychainAccessibilityMigration.completedDefaultsKey))

        backend.forcedUpdateStatusByKey = [:]
        XCTAssertEqual(sut.runIfNeeded(), .completed(migrated: 1))
        XCTAssertEqual(backend.items[sessionKey]?.accessibility, afterFirstUnlock)
        XCTAssertTrue(defaults.bool(forKey: KeychainAccessibilityMigration.completedDefaultsKey))
    }

    func testListingFailureWhileLockedIsNotRecorded() {
        seedLegacyItems()
        backend.isLocked = true
        let sut = makeSUT()

        XCTAssertEqual(sut.runIfNeeded(), .failed)
        XCTAssertFalse(defaults.bool(forKey: KeychainAccessibilityMigration.completedDefaultsKey))

        backend.isLocked = false
        XCTAssertEqual(sut.runIfNeeded(), .completed(migrated: 2))
    }
}

// MARK: - Maintenance

@MainActor
final class KeychainProtectedDataMaintenanceTests: XCTestCase {

    private let whenUnlocked = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    private let afterFirstUnlock = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    func testWaitsForProtectedDataThenMigratesAndFlushes() {
        let backend = FakeKeychainBackend()
        backend.items["credentials.a"] = .init(data: Data("old".utf8), accessibility: whenUnlocked)
        backend.isLocked = true
        let keychain = KeychainStorable(service: "test.service", backend: backend)
        keychain.set("new", forKey: "credentials.a")

        let suiteName = "KeychainProtectedDataMaintenanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = NotificationCenter()
        var available = false
        let sut = KeychainProtectedDataMaintenance(notificationCenter: center, isProtectedDataAvailable: { available })
        defer { sut.stop() }

        sut.start(with: keychain, defaults: defaults)
        XCTAssertTrue(backend.calls.filter { if case .copyMatching = $0 { return true } else { return false } }.isEmpty,
                      "Nothing runs before protected data is available")
        XCTAssertTrue(keychain.hasPendingOperations)

        backend.isLocked = false
        available = true
        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)

        XCTAssertFalse(keychain.hasPendingOperations)
        XCTAssertEqual(backend.items["credentials.a"], .init(data: Data("new".utf8), accessibility: afterFirstUnlock))
        XCTAssertTrue(defaults.bool(forKey: KeychainAccessibilityMigration.completedDefaultsKey))
    }

    func testIgnoresStoresThatAreNotTheRealKeychain() {
        let center = NotificationCenter()
        let sut = KeychainProtectedDataMaintenance(notificationCenter: center, isProtectedDataAvailable: { true })
        defer { sut.stop() }
        let suiteName = "KeychainProtectedDataMaintenanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        sut.start(with: MockKeyStorable(), defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: KeychainAccessibilityMigration.completedDefaultsKey))
    }
}
