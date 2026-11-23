import SwiftUI

// MARK: - Content

/// What the App Store Connect email and password screen says about the
/// password (flag `accountConnectionGuide`): the trust panel above the fields
/// and the steps of "How Your Password Is Used".
///
/// Claims must match the code and `PRIVACY.md`: the password goes only to
/// Apple (never through the developer), is saved only when "Save password on
/// this device" is on (`ApplePasswordKeychainStore`: Keychain, this device
/// only, readable while unlocked), and is never logged or sent with analytics
/// or crash reports. No private endpoint is named, and the only links are the
/// repository, `ApplePasswordKeychainStore.swift` and the privacy policy.
enum ApplePasswordTrustContent {

    /// The trust panel's facts.
    static var panelItems: [StackTrustItem] {
        [
            StackTrustItem(systemImage: "lock.fill",
                           text: String(localized: "Saved only if you choose, and only in this device's Keychain",
                                        comment: "Trust panel of the App Store Connect email and password screen: where the password is kept.")),
            StackTrustItem(systemImage: "icloud.slash",
                           text: String(localized: "Never synced through iCloud or sent to a StackConnect server",
                                        comment: "Trust panel of the App Store Connect email and password screen.")),
            StackTrustItem(systemImage: "paperplane.fill",
                           text: String(localized: "Sent only to Apple, to sign you in",
                                        comment: "Trust panel of the App Store Connect email and password screen: where the password goes.")),
            StackTrustItem(systemImage: "chevron.left.forwardslash.chevron.right",
                           text: String(localized: "Open source and auditable",
                                        comment: "Trust panel of the App Store Connect email and password screen: anyone can read the code."))
        ]
    }

    /// One step of "How Your Password Is Used".
    struct Step: Identifiable, Hashable {
        let number: Int
        let title: String
        let detail: String
        var link: StackExternalLinkItem?

        var id: Int { number }
    }

    /// "How Your Password Is Used", in order.
    static var steps: [Step] {
        [
            Step(
                number: 1,
                title: String(localized: "You type it on this device",
                              comment: "How Your Password Is Used, step 1 title."),
                detail: String(localized: "Only on this screen. StackConnect has no server of its own, so your password never passes through the developer.",
                               comment: "How Your Password Is Used, step 1 detail."),
                link: .sourceCode
            ),
            Step(
                number: 2,
                title: String(localized: "Sent only to Apple, over an encrypted connection, to sign you in",
                              comment: "How Your Password Is Used, step 2 title."),
                detail: String(localized: "Never to the developer or anyone else.",
                               comment: "How Your Password Is Used, step 2 detail.")
            ),
            Step(
                number: 3,
                title: String(localized: "Saved only if you turn on \"Save password on this device\"",
                              comment: "How Your Password Is Used, step 3 title. \"Save password on this device\" is the toggle of the password screen: use its translation."),
                detail: String(localized: "It's then kept in this device's Keychain, readable only while the device is unlocked, and never synced through iCloud or restored to other devices. It's deleted with the last account that uses it.",
                               comment: "How Your Password Is Used, step 3 detail."),
                link: .applePasswordKeychainStore
            ),
            Step(
                number: 4,
                title: String(localized: "Never in logs, analytics or crash reports",
                              comment: "Credentials (connection guide) or the Apple ID password (How Your Password Is Used) never appear in logs, analytics or crash reports."),
                detail: String(localized: "Two-factor codes aren't saved at all.",
                               comment: "How Your Password Is Used, step 4 detail."),
                link: .privacyPolicy
            )
        ]
    }
}

// MARK: - View

/// "How Your Password Is Used": what happens to the App Store Connect
/// password, step by step, each linked to where it happens (the code or the
/// privacy policy). Presented as a sheet by the email and password screen.
struct ApplePasswordUsageView: View {

    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ApplePasswordTrustContent.steps) { step in
                        StackNumberedStepRow(number: step.number, title: step.title, detail: step.detail) {
                            if let link = step.link {
                                StackExternalLink(link, screen: .applePasswordUsage)
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "How Your Password Is Used",
                                    comment: "Title of the sheet explaining what happens to the App Store Connect password, and of the link that opens it."))
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(.applePasswordUsage)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    StackTrackedButton(String(localized: "Done"), button: .done, on: .applePasswordUsage, action: onDone)
                }
            }
        }
    }
}

#Preview {
    ApplePasswordUsageView(onDone: {})
}
