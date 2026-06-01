import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// Read-only tool: lists the apps cached on the device, optionally filtered by
/// name. Backed entirely by local storage via `AppResolving`.
@available(iOS 26.0, *)
struct ListAppsTool: Tool {

    let name = "list_apps"
    let description = """
    Lists the user's App Store Connect apps cached on this device, with each \
    app's current App Store status and latest version. Optionally filter by app \
    name or bundle id.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Text to filter apps by name or bundle id. Pass an empty string to list all apps.")
        var nameFilter: String
    }

    let resolver: any AppResolving

    func call(arguments: Arguments) async throws -> String {
        await run(nameFilter: arguments.nameFilter)
    }

    /// Core logic, decoupled from the generated `Arguments` type for testing.
    func run(nameFilter: String?) async -> String {
        let query = nameFilter ?? ""
        let apps = await resolver.apps(matching: query)

        guard !apps.isEmpty else {
            return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "No apps are synced on this device yet."
                : "No app matches “\(query)”."
        }

        let lines = apps
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .prefix(50)
            .map { app -> String in
                let version = app.versionString.map { "v\($0)" } ?? "—"
                let state = app.appStoreState?.displayName ?? "Unknown status"
                return "• \(app.name) (\(app.bundleId)) — \(version), \(state)"
            }

        return lines.joined(separator: "\n")
    }
}
#endif
