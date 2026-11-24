import Foundation
import ObjectiveC
import StackProtocols
import UIKit

// MARK: - Bootstrap

/// Turns the network audit on for this launch, before anything opens a
/// connection (`StackConnectApp.init`, ahead of Firebase).
///
/// Off — nothing installed, nothing recorded — when the `networkAudit` flag is
/// OFF, in a unit-test host and in the DEBUG fake data mode (whose network
/// guard, `FakeNetworkURLProtocol`, must stay the first protocol of
/// `URLSession.shared`).
enum NetworkAuditBootstrap {

    @MainActor
    static func install(
        featureFlags: FeatureFlags = .shared,
        isUnitTestHost: Bool,
        isFakeDataMode: Bool
    ) {
        guard featureFlags.isEnabled(.networkAudit), !isUnitTestHost, !isFakeDataMode else { return }

        let recorder = NetworkAuditRecorder(
            store: FileNetworkAuditStore.shared,
            settings: NetworkAuditSettings.shared,
            vault: NetworkAuditSecretVault(keychain: KeychainStorable.shared),
            accounts: NetworkAuditAccountDirectory.live()
        )
        NetworkAuditRecorder.shared = recorder
        NetworkAuditSessionInstaller.install(sink: recorder)

        // Retention: at launch and every time the app comes back. Once, what
        // older versions kept of StackConnect's own values (telemetry secrets,
        // bundle ID, Firebase project) is dropped from disk.
        let scrubKey = "networkAudit.didScrubAppValues.v2"
        let needsScrub = !UserDefaults.standard.bool(forKey: scrubKey)
        Task.detached(priority: .utility) {
            await recorder.purgeExpired()
            if needsScrub {
                await recorder.scrubAppTelemetrySecrets()
                UserDefaults.standard.set(true, forKey: scrubKey)
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            Task.detached(priority: .utility) { await recorder.purgeExpired() }
        }
        Log.print.info("[NetworkAudit] Recording network traffic on this device")
    }
}

// MARK: - Session installer

/// Puts `NetworkAuditURLProtocol` in front of the app's sessions:
///
/// - `URLSession.shared`: `URLProtocol.registerClass`.
/// - Every session built from `URLSessionConfiguration.default` / `.ephemeral`
///   — the app's own (`GoogleOAuthHTTP`, `APIProviderFirebase`'s request
///   executor) and the Firebase SDKs' (Analytics, Crashlytics settings,
///   Remote Config, Installations) — by swizzling both class getters to
///   prepend the protocol to `protocolClasses` (the netfox approach). The
///   swizzles chain: netfox (DEBUG) swizzling the same getters later wraps
///   ours, and the handled-request marker keeps each exchange recorded once.
///
/// Not covered: background `URLSession`s (URLProtocol never runs there —
/// Crashlytics report uploads may use one), `ASWebAuthenticationSession`
/// (the Google sign-in page), and the Rust core's own HTTP client.
enum NetworkAuditSessionInstaller {

    nonisolated(unsafe) private static var isInstalled = false

    static func install(sink: NetworkAuditExchangeSink) {
        NetworkAuditURLProtocol.sink = sink
        guard !isInstalled else { return }
        isInstalled = true
        URLProtocol.registerClass(NetworkAuditURLProtocol.self)
        wrapGetter(#selector(getter: URLSessionConfiguration.default))
        wrapGetter(#selector(getter: URLSessionConfiguration.ephemeral))
    }

    /// Prepends the recorder to `configuration`'s protocol classes (once).
    static func inject(into configuration: URLSessionConfiguration) {
        let others = (configuration.protocolClasses ?? []).filter {
            ObjectIdentifier($0) != ObjectIdentifier(NetworkAuditURLProtocol.self)
        }
        configuration.protocolClasses = [NetworkAuditURLProtocol.self] + others
    }

    private typealias ConfigurationGetter = @convention(c) (AnyClass, Selector) -> URLSessionConfiguration

    /// Replaces the class getter `selector` with a block that calls the
    /// previous implementation, then injects the recorder.
    private static func wrapGetter(_ selector: Selector) {
        guard let method = class_getClassMethod(URLSessionConfiguration.self, selector) else {
            Log.print.error("[NetworkAudit] Could not wrap a URLSessionConfiguration getter")
            return
        }
        let original = unsafeBitCast(method_getImplementation(method), to: ConfigurationGetter.self)
        let block: @convention(block) (AnyClass) -> URLSessionConfiguration = { type in
            let configuration = original(type, selector)
            inject(into: configuration)
            return configuration
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
