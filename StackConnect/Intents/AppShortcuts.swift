import AppIntents

struct StackConnectShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReleaseVersionIntent(),
            phrases: [
                "Release app in \(.applicationName)",
                "Release pending version in \(.applicationName)",
                "Liberar app no \(.applicationName)",
                "Liberar versão pendente no \(.applicationName)"
            ],
            shortTitle: "Release Version",
            systemImageName: "arrow.up.circle"
        )

        AppShortcut(
            intent: RejectVersionIntent(),
            phrases: [
                "Reject app in \(.applicationName)",
                "Reject pending version in \(.applicationName)",
                "Rejeitar app no \(.applicationName)",
                "Rejeitar versão pendente no \(.applicationName)"
            ],
            shortTitle: "Reject Version",
            systemImageName: "xmark.circle"
        )
    }
}
