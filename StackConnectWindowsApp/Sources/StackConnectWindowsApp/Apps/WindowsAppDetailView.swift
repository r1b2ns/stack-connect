import SwiftCrossUI
import StackHomeCore
import WindowsAppCore

#if canImport(os)
import os
#endif

// T-W12 — App Detail screen for the Windows GUI.
//
// Displays the detail of a single app: a header card (icon glyph, name,
// bundle ID, colored status badge, status text, version), a platform section
// ("iOS" + "See All" -> Coming Soon), the option sections from the model
// (General, App Store, Analytics, TestFlight), and Favorite/Archive actions.
//
// The view binds to `WindowsAppDetailModel` (T-W11) which owns the app data,
// loading/error state, sections, and mutation intents (toggleFavorite,
// archiveApp). The view is purely declarative -- all mutations go through the
// model's intents. Navigation uses `WindowsHomeCoordinator` (T-W03).
//
// Layout follows the Windows app convention: content capped at 860px, padded
// 16px, with a `ScrollView` + `VStack`. The toolbar uses
// `WindowsBackButtonView` for the "< Back" action (pops to prior screen).
//
// Option row tap behavior:
//   - "Ratings and Reviews" (isFunctional == true) -> ratingsAndReviews route
//   - All other options (isFunctional == false) -> comingSoon(title:) route
//
// Archive flow (AC-W09-3): the Archive button pushes an
// `archiveAppDetailConfirm` route via the coordinator. On confirm, the
// confirmation screen calls `model.archiveApp(appId:accountId:)` and pops
// back to the apps list. This uses a PUSHED ROUTE (TC-072), not an
// alert/sheet.
//
// TC-070: Refresh is an explicit button in the toolbar. There is NO
// pull-to-refresh (SwiftCrossUI has no pull-to-refresh support).

struct WindowsAppDetailView: View {

    /// The app id this detail displays.
    let appId: String
    /// The account id the app belongs to.
    let accountId: String
    /// Navigation coordinator -- Back pops, option taps push sub-routes.
    @State private var coordinator: WindowsHomeCoordinator
    /// The app detail model. Observed via `@State` so the view redraws when
    /// the model's `@Published` properties change. The same instance is shared
    /// with the archive confirmation view via the RootView's
    /// `AppDetailModelCache`.
    @State private var model: WindowsAppDetailModel

    init(
        appId: String,
        accountId: String,
        coordinator: WindowsHomeCoordinator,
        model: WindowsAppDetailModel
    ) {
        self.appId = appId
        self.accountId = accountId
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                toolbar
                syncErrorBanner
                content
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
        .task {
            await model.loadAppIfNeeded(appId: appId, accountId: accountId)
        }
    }

    // MARK: - Toolbar (back + title + Favorite + Archive + Refresh)

    /// Header: "< Back" on the left, Favorite toggle + Archive + Refresh
    /// buttons on the right. App name as the title below.
    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack {
                WindowsBackButtonView(onBack: { coordinator.pop() })
                Spacer()
                // Favorite toggle (AC-W06-4 / AC-W09-1 / TC-020)
                if let app = model.uiState.app {
                    Button(app.isFavorite ? "\u{2605} Favorite" : "\u{2606} Favorite") {
                        Task {
                            await model.toggleFavorite(appId: appId)
                        }
                    }
                    .foregroundColor(app.isFavorite ? .yellow : .gray)
                }
                // Archive button (AC-W06-4 / AC-W09-3 / TC-021)
                if model.uiState.app != nil {
                    Button("Archive") {
                        let appName = model.uiState.app?.name ?? ""
                        coordinator.push(
                            .archiveAppDetailConfirm(
                                appId: appId,
                                appName: appName,
                                accountId: accountId
                            )
                        )
                    }
                    .foregroundColor(.orange)
                }
                Button("Refresh") {
                    Task {
                        await model.loadAppIfNeeded(appId: appId, accountId: accountId)
                    }
                }
            }
            HStack {
                Text(model.uiState.app?.name ?? "App Detail")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
        }
    }

    // MARK: - Sync Error Banner (TC-022: non-blocking sync-error)

    /// Inline error banner shown when a sync fails. Uses the InfoBar convention
    /// (4px colored left border + message). Cached detail remains visible below.
    @ViewBuilder
    private var syncErrorBanner: some View {
        if let error = model.uiState.syncError {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 4)
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Text(error)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(12)
            }
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }
    }

    // MARK: - Content (loading / populated)

    @ViewBuilder
    private var content: some View {
        if model.uiState.isLoading && model.uiState.app == nil {
            // First load -> loading indicator, no partial/stale content (TC-022)
            loadingState
        } else if let app = model.uiState.app {
            populatedState(app: app)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading app detail...")
                .foregroundColor(.gray)
            Spacer()
        }
    }

    // MARK: - Populated State

    @ViewBuilder
    private func populatedState(app: AppModel) -> some View {
        headerCard(app: app)
        platformSection(app: app)
        optionSections
    }

    // MARK: - Header Card (AC-W06-1 / TC-014)

    /// Header card: app icon glyph, name, bundle ID, colored status badge +
    /// status text, and version.
    private func headerCard(app: AppModel) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // App icon fallback glyph (no remote image in SwiftCrossUI)
                Text(iconGlyph(for: app))
                    .font(.title)
                    .frame(width: 48, height: 48)
                    .background(Color.blue.opacity(0.10))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    // App name
                    Text(app.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    // Bundle ID
                    Text(app.bundleId)
                        .foregroundColor(.gray)

                    // Status badge + status text
                    if let state = app.appStoreState {
                        HStack(spacing: 8) {
                            WindowsStatusBadge(state: state)
                            Text(state.displayName)
                                .foregroundColor(.gray)
                        }
                    }

                    // Version
                    if let version = app.versionString, !version.isEmpty {
                        Text("v\(version)")
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .cornerRadius(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
    }

    // MARK: - Platform Section (AC-W06-3 / TC-019)

    /// Platform section: "iOS" label with a "See All" affordance that pushes
    /// comingSoon(title: "Platforms"). No functional navigation.
    private func platformSection(app: AppModel) -> some View {
        VStack(spacing: 8) {
            WindowsSectionHeader(title: "Platforms") {
                coordinator.push(.comingSoon(title: "Platforms"))
            }

            HStack(spacing: 10) {
                Text("\u{1F4F1}") // mobile phone emoji as platform glyph
                Text(app.platform ?? "iOS")
                Spacer()
                Button("See All") {
                    coordinator.push(.comingSoon(title: "Platforms"))
                }
            }
            .padding(8)
            .background(Color(white: 0.94))
            .cornerRadius(6)
        }
    }

    // MARK: - Option Sections (AC-W06-2 / TC-015)

    /// Renders the option sections from `uiState.sections` using
    /// `WindowsSectionHeader` + `WindowsOptionRow` for each row.
    /// Leaf sections (Analytics, TestFlight) with no options are rendered
    /// as a single tappable row.
    @ViewBuilder
    private var optionSections: some View {
        ForEach(model.uiState.sections, id: \.self) { section in
            sectionView(section)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: AppDetailSection) -> some View {
        WindowsSectionHeader(title: section.title)

        if section.options.isEmpty {
            // Leaf section (Analytics, TestFlight): render as a single tappable
            // option row that navigates to Coming Soon.
            WindowsOptionRow(
                glyph: glyphForSection(section.title),
                label: section.title,
                action: {
                    coordinator.push(.comingSoon(title: section.title))
                }
            )
        } else {
            ForEach(section.options, id: \.self) { option in
                optionRow(option)
            }
        }
    }

    // MARK: - Option Row Tap Behavior (AC-W07-1/2, AC-W08-1/2, TC-016..018)

    /// A single option row. Functional options navigate to real screens;
    /// non-functional options push comingSoon(title:).
    private func optionRow(_ option: AppDetailOption) -> some View {
        WindowsOptionRow(
            glyph: glyphForOption(option.title),
            label: option.title,
            action: {
                if option.isFunctional {
                    // AC-W07-1: "Ratings and Reviews" navigates with correct params
                    if option.title == "Ratings and Reviews" {
                        let bundleId = model.uiState.app?.bundleId ?? ""
                        coordinator.push(
                            .ratingsAndReviews(
                                appId: appId,
                                bundleId: bundleId,
                                accountId: accountId
                            )
                        )
                    }
                } else {
                    // AC-W08-1/2: non-functional options -> comingSoon
                    coordinator.push(.comingSoon(title: option.title))
                }
            }
        )
    }

    // MARK: - Glyph Helpers

    /// A graceful fallback when no remote icon is available. Uses the first
    /// letter of the app name (uppercased), or a generic app glyph.
    private func iconGlyph(for app: AppModel) -> String {
        if let first = app.name.first {
            return String(first).uppercased()
        }
        return "\u{25A0}" // filled square as generic app glyph
    }

    /// Maps section titles to text glyphs (no SF Symbols on Windows).
    private func glyphForSection(_ title: String) -> String {
        switch title {
        case "General":    return "\u{2699}"  // gear
        case "App Store":  return "\u{1F6CD}" // shopping bag
        case "Analytics":  return "\u{1F4CA}" // bar chart
        case "TestFlight": return "\u{2708}"  // airplane
        default:           return "\u{25B6}"  // play triangle
        }
    }

    /// Maps option titles to text glyphs (no SF Symbols on Windows).
    private func glyphForOption(_ title: String) -> String {
        switch title {
        case "App Information":      return "\u{2139}"  // info
        case "App Review":           return "\u{1F50D}" // magnifying glass
        case "History":              return "\u{1F4C5}" // calendar
        case "App Privacy":          return "\u{1F512}" // lock
        case "App Accessibility":    return "\u{267F}"  // wheelchair
        case "Ratings and Reviews":  return "\u{2B50}"  // star
        default:                     return "\u{25B6}"  // play triangle
        }
    }
}
