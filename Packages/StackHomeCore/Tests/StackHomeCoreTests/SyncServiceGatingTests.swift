import XCTest
import StackProtocols
@testable import StackHomeCore

/// T-E2 — Structural-gating coverage for the Foundation-pure `StackHomeCore`
/// package (artifact §3.6 / §4, US-010).
///
/// These tests are the *gap fill* on top of the existing `SyncServiceTests`
/// (pipeline transitions + coalescing). They prove the invariants that keep the
/// package buildable on the Windows toolchain and SDK-free:
///
/// - **TC-056** — no forbidden platform imports (`SwiftUI`/`UIKit`/`WidgetKit`/
///   `UserNotifications`/`AppKit`) anywhere in `Sources/`, except behind an
///   allowed `#if canImport(...)` gate.
/// - **TC-057** — any `import Combine` appears only inside a
///   `#if canImport(Combine)` block, and `SyncService`'s public state API is
///   Combine-free (`onStateChanged` callback + `AsyncStream<SyncState>`).
/// - **TC-058** — the shared `HomeWidget` protocol has no `makeView()`
///   requirement.
/// - **Gated side effects off-platform** — on the non-Apple path the injected
///   side-effect seam still drives the pure state transitions but the Apple-only
///   `syncDidStart` is NOT invoked (no WidgetKit/UIKit/UserNotifications work).
///
/// The source-scan guards read the package's own `Sources/` tree at test time
/// (path derived from `#filePath`, so they're robust to the checkout location)
/// and fail if a regression reintroduces a forbidden import. The *Windows build*
/// half of TC-056 is VM-only and intentionally out of scope here — these guards
/// cover the import-absence invariant that makes that build possible.
final class SyncServiceGatingTests: XCTestCase {

    // MARK: - Source tree resolution

    /// Absolute URL of `Sources/StackHomeCore`, derived from this test file's
    /// location: `.../Tests/StackHomeCoreTests/<thisFile>` → up 3 → package root
    /// → `Sources/StackHomeCore`.
    private static func sourcesDirectory(file: StaticString = #filePath) -> URL {
        let thisFile = URL(fileURLWithPath: "\(file)")
        let packageRoot = thisFile
            .deletingLastPathComponent()   // SyncServiceGatingTests.swift
            .deletingLastPathComponent()   // StackHomeCoreTests
            .deletingLastPathComponent()   // Tests
        return packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("StackHomeCore")
    }

    /// Every `.swift` file under `Sources/StackHomeCore`, with its contents.
    private func swiftSources() throws -> [(url: URL, lines: [String])] {
        let root = Self.sourcesDirectory()
        let fm = FileManager.default
        var isDir: ObjCBool = false
        XCTAssertTrue(
            fm.fileExists(atPath: root.path, isDirectory: &isDir) && isDir.boolValue,
            "Could not resolve Sources/StackHomeCore at \(root.path) — fix the #filePath-based path math."
        )

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            XCTFail("Failed to enumerate \(root.path)")
            return []
        }

        var results: [(URL, [String])] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            results.append((url, contents.components(separatedBy: .newlines)))
        }
        XCTAssertFalse(results.isEmpty, "No Swift sources found under \(root.path) — the scan would pass vacuously.")
        return results
    }

    /// True if `line`, trimmed, is an actual import statement for `module`
    /// (not a comment or a substring of another identifier).
    private func isImportLine(_ line: String, of module: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("*"), !trimmed.hasPrefix("/*") else {
            return false
        }
        // Matches `import Combine`, `@testable import Combine`,
        // `import struct Combine.Foo`, etc.
        let tokens = trimmed.split(whereSeparator: { $0 == " " }).map(String.init)
        guard let importIdx = tokens.firstIndex(of: "import") else { return false }
        // The module name is the token immediately after `import`, possibly
        // preceded by a submodule kind (struct/class/...). Check any token
        // equals the module or starts with `module.`.
        for token in tokens[(importIdx + 1)...] {
            if token == module || token.hasPrefix("\(module).") { return true }
        }
        return false
    }

    /// For each source line index that imports `module`, walk upward to decide
    /// whether the line sits inside a `#if canImport(<allowedGate>)` block that
    /// is still open at that point. Returns the file URLs where an ungated
    /// import was found.
    private func ungatedImports(
        of module: String,
        allowedGate: String,
        in sources: [(url: URL, lines: [String])]
    ) -> [URL] {
        var offenders: [URL] = []
        for (url, lines) in sources {
            for (idx, line) in lines.enumerated() where isImportLine(line, of: module) {
                if !isInsideCanImport(allowedGate, atLine: idx, lines: lines) {
                    offenders.append(url)
                    break
                }
            }
        }
        return offenders
    }

    /// Tracks the `#if`/`#endif` nesting above `targetLine` and returns true iff
    /// there is an open `#if canImport(<gate>)` (or `#elseif canImport(<gate>)`)
    /// branch enclosing it. Conservative: any other `#if` still counts as nesting
    /// so `#endif` matching stays balanced, but only a `canImport(<gate>)`
    /// condition satisfies the gate.
    private func isInsideCanImport(_ gate: String, atLine targetLine: Int, lines: [String]) -> Bool {
        var stack: [Bool] = []   // true == this open conditional is the allowed canImport gate
        let needle = "canImport(\(gate))"
        for i in 0..<targetLine {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#if") {
                stack.append(t.contains(needle))
            } else if t.hasPrefix("#elseif") {
                if !stack.isEmpty { stack[stack.count - 1] = t.contains(needle) }
            } else if t.hasPrefix("#else") {
                if !stack.isEmpty { stack[stack.count - 1] = false }
            } else if t.hasPrefix("#endif") {
                if !stack.isEmpty { stack.removeLast() }
            }
        }
        return stack.contains(true)
    }

    // MARK: - TC-056: no forbidden platform imports

    /// TC-056 (import-absence invariant). None of the UI/platform frameworks may
    /// be imported in core sources, unless wrapped in their own `#if canImport`
    /// gate (none are today; the gate carve-out keeps the guard honest if a
    /// future Apple-only convenience is added behind a gate).
    func testNoForbiddenPlatformImports() throws {
        let sources = try swiftSources()
        let forbidden = ["SwiftUI", "UIKit", "WidgetKit", "UserNotifications", "AppKit"]

        for module in forbidden {
            let offenders = ungatedImports(of: module, allowedGate: module, in: sources)
            XCTAssertTrue(
                offenders.isEmpty,
                "Forbidden ungated `import \(module)` in StackHomeCore sources: "
                + offenders.map { $0.lastPathComponent }.joined(separator: ", ")
                + ". Core must stay Foundation-pure for the Windows toolchain (US-010 AC-1)."
            )
        }
    }

    /// TC-056 (focused on the AC-4 named types). `SyncService.swift` and
    /// `HomeViewModel.swift` specifically must be free of the forbidden imports.
    func testSyncServiceAndHomeViewModelHaveNoForbiddenImports() throws {
        let sources = try swiftSources()
        let targets = ["SyncService.swift", "HomeViewModel.swift"]
        let forbidden = ["SwiftUI", "UIKit", "WidgetKit", "UserNotifications", "AppKit"]

        let relevant = sources.filter { targets.contains($0.url.lastPathComponent) }
        XCTAssertEqual(
            Set(relevant.map { $0.url.lastPathComponent }), Set(targets),
            "Expected to scan \(targets) but found \(relevant.map { $0.url.lastPathComponent })."
        )

        for (url, lines) in relevant {
            for module in forbidden {
                let hasUngated = lines.enumerated().contains { idx, line in
                    isImportLine(line, of: module) && !isInsideCanImport(module, atLine: idx, lines: lines)
                }
                XCTAssertFalse(
                    hasUngated,
                    "\(url.lastPathComponent) must not import \(module) (US-010 AC-4)."
                )
            }
        }
    }

    // MARK: - TC-057: Combine is gated

    /// TC-057 (source guard). Any `import Combine` in core sources must live
    /// inside a `#if canImport(Combine)` block. Passes vacuously today (core has
    /// zero Combine imports) and guards the bridge if one is later added.
    func testCombineImportsAreGatedBehindCanImport() throws {
        let sources = try swiftSources()
        let offenders = ungatedImports(of: "Combine", allowedGate: "Combine", in: sources)
        XCTAssertTrue(
            offenders.isEmpty,
            "Ungated `import Combine` in: "
            + offenders.map { $0.lastPathComponent }.joined(separator: ", ")
            + ". Combine must only appear under `#if canImport(Combine)` (US-010 AC-4)."
        )
    }

    /// TC-057 (API surface). `SyncService` exposes its state Combine-free: a
    /// synchronous `state` snapshot, an `onStateChanged` callback, and an
    /// `AsyncStream<SyncState>`. Exercising these without importing Combine here
    /// documents that no Combine type is required to consume the service.
    @MainActor
    func testSyncServicePublicStateApiRequiresNoCombine() async throws {
        let storage = GatingInMemoryStorage()
        let keychain = GatingInMemoryKeychain()
        let service = SyncService<GatingStubCredentials>(
            storage: storage,
            keychain: keychain,
            appleConnectionFactory: { _ in GatingStubSyncing() }
        )

        // Synchronous snapshot — no publisher.
        XCTAssertFalse(service.state.isSyncing)

        // Callback seam — a plain closure, not an AnyPublisher/sink.
        var callbackFired = false
        service.onStateChanged = { _ in callbackFired = true }

        // AsyncStream seam — replays current value, no Combine subscription.
        var iterator = service.states.makeAsyncIterator()
        let replayed = await iterator.next()
        XCTAssertEqual(replayed?.isSyncing, false, "states must replay the current idle snapshot")

        let firebase = AccountModel(name: "FB", providerType: .firebase)
        try await storage.save(firebase, id: firebase.id)
        await service.syncAll().value

        XCTAssertTrue(callbackFired, "onStateChanged callback must drive transitions without Combine")
    }

    // MARK: - TC-058: no makeView() in the shared protocol

    /// TC-058 (source guard). The shared `HomeWidget` protocol definition must
    /// not declare a `makeView()` requirement (US-010 AC-5). Compilation already
    /// enforces the absence of the requirement; this documents and guards it
    /// against an accidental reintroduction.
    func testHomeWidgetProtocolHasNoMakeView() throws {
        let sources = try swiftSources()
        guard let widget = sources.first(where: { $0.url.lastPathComponent == "HomeWidget.swift" }) else {
            return XCTFail("HomeWidget.swift not found under Sources/StackHomeCore.")
        }

        // Inspect only the protocol body, ignoring doc-comment mentions of the
        // (deliberately removed) `makeView` so the prose explaining the removal
        // doesn't trip the guard.
        let codeLines = widget.lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("*") && !$0.hasPrefix("/*") }

        let hasMakeView = codeLines.contains { $0.contains("makeView") }
        XCTAssertFalse(
            hasMakeView,
            "HomeWidget protocol must not declare `makeView()` — view-building is platform-specific (US-010 AC-5)."
        )
    }

    // MARK: - Gated side effects: off-platform path

    /// On the non-Apple path (zero Apple accounts) the pure pipeline still
    /// settles idle→syncing→idle and updates `lastSyncedAt`, but the Apple-only
    /// `syncDidStart` side effect (the seam that fronts WidgetKit / UIKit /
    /// UserNotifications work) is NOT invoked. Negative counterpart to the
    /// existing `testSideEffectsAreInvoked`.
    @MainActor
    func testAppleSideEffectsNotInvokedWhenNoAppleAccounts() async throws {
        let storage = GatingInMemoryStorage()
        let keychain = GatingInMemoryKeychain()
        let effects = GatingSpySideEffects()

        let service = SyncService<GatingStubCredentials>(
            storage: storage,
            keychain: keychain,
            appleConnectionFactory: { _ in GatingStubSyncing() },
            sideEffects: effects
        )

        // Only a non-Apple account exists — the Apple sync body must be skipped.
        let firebase = AccountModel(name: "FB", providerType: .firebase)
        try await storage.save(firebase, id: firebase.id)

        var sawSyncing = false
        service.onStateChanged = { if $0.isSyncing { sawSyncing = true } }

        await service.syncAll().value

        // Pure transitions still fire.
        XCTAssertTrue(sawSyncing, "pure state must still flip to syncing=true off the Apple path")
        XCTAssertFalse(service.state.isSyncing, "must settle back to idle")
        XCTAssertNotNil(service.state.lastSyncedAt, "lastSyncedAt must update even with no Apple accounts")

        // Apple-only side effect (WidgetKit/UIKit/UserNotifications front) does NOT run.
        let didStart = await effects.didStart
        XCTAssertFalse(didStart, "syncDidStart must NOT fire when there are no Apple accounts to sync")
        // syncDidFinish still runs to record completion (no Apple-only work in the no-op).
        let didFinish = await effects.didFinish
        XCTAssertTrue(didFinish, "syncDidFinish should still record sync completion")
    }
}

// MARK: - Test doubles (file-private to avoid clashing with SyncServiceTests)

private struct GatingStubCredentials: Codable, Sendable {
    let issuerID: String
}

private actor GatingSpySideEffects: SyncSideEffects {
    private(set) var didStart = false
    private(set) var didFinish = false
    func syncDidStart(mode: SyncMode, accountCount: Int) async { didStart = true }
    func syncDidFinish(mode: SyncMode, changes: SyncChange) async { didFinish = true }
}

private final class GatingStubSyncing: AppleAccountSyncing, @unchecked Sendable {
    func fetchApps() async throws -> [AppInfo] { [] }
    func fetchIconUrl(appId: String) async -> String? { nil }
    func fetchAppStoreVersions(appId: String, limit: Int) async throws -> [AppStoreVersionModel] { [] }
    func fetchRecentReviews(appId: String, limit: Int) async throws -> [CustomerReviewModel] { [] }
    func fetchPhasedRelease(versionId: String) async throws -> PhasedReleaseModel? { nil }
}

private final class GatingInMemoryStorage: PersistentStorable, @unchecked Sendable {
    private var store: [String: Data] = [:]
    private let lock = NSLock()

    func save<T: Codable>(_ item: T, id: String) async throws {
        let data = try JSONEncoder().encode(item)
        lock.lock(); defer { lock.unlock() }
        store["\(String(describing: T.self)).\(id)"] = data
    }
    func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T? {
        lock.lock(); let data = store["\(String(describing: T.self)).\(id)"]; lock.unlock()
        guard let data else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T] {
        let key = String(describing: T.self)
        lock.lock(); let datas = store.filter { $0.key.hasPrefix("\(key).") }.values; lock.unlock()
        return try datas.map { try JSONDecoder().decode(T.self, from: $0) }
    }
    func delete<T: Codable>(_ type: T.Type, id: String) async throws {
        lock.lock(); defer { lock.unlock() }
        store["\(String(describing: T.self)).\(id)"] = nil
    }
    func deleteAll<T: Codable>(_ type: T.Type) async throws {
        lock.lock(); defer { lock.unlock() }
        let prefix = "\(String(describing: T.self))."
        for key in store.keys where key.hasPrefix(prefix) { store[key] = nil }
    }
}

private final class GatingInMemoryKeychain: KeyStorable, @unchecked Sendable {
    func string(forKey key: String) -> String? { nil }
    func int(forKey key: String) -> Int? { nil }
    func double(forKey key: String) -> Double? { nil }
    func bool(forKey key: String) -> Bool? { nil }
    func data(forKey key: String) -> Data? { nil }
    func set(_ value: Any?, forKey key: String) {}
    func removeObject(forKey key: String) {}
}
