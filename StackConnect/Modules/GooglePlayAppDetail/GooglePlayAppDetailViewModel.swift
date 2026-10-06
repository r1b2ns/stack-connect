import Foundation

// MARK: - Protocol

@MainActor
protocol GooglePlayAppDetailViewModelProtocol: ObservableObject {
    var uiState: GooglePlayAppDetailUiState { get set }
    /// Reads the local cache only — this screen never calls Google.
    func load() async
    /// `nil` when the user may open `section`, otherwise why not. A pure query.
    func denial(for section: GooglePlayAppDetailSection) -> String?
    /// Shows the "Permission Denied" alert with `message`.
    func presentDenial(_ message: String)
}

// MARK: - Sections

/// Menu entries of a Google Play app.
enum GooglePlayAppDetailSection: CaseIterable, Identifiable {
    case ratingsReviews
    case storeListings
    case tracks
    case appDetails

    var id: Self { self }

    var title: String {
        switch self {
        case .ratingsReviews: return String(localized: "Ratings & Reviews")
        case .storeListings:  return String(localized: "Store Listings")
        case .tracks:         return String(localized: "Tracks & Releases")
        case .appDetails:     return String(localized: "App Details")
        }
    }

    var icon: String {
        switch self {
        case .ratingsReviews: return "star.fill"
        case .storeListings:  return "text.below.photo.fill"
        case .tracks:         return "square.stack.3d.up.fill"
        case .appDetails:     return "info.circle.fill"
        }
    }

    /// Read through a temporary Play edit, which cancels an edit the same
    /// service account has open for the app (see `GooglePlayAppDetailsFetching`).
    /// These sections load only when the user opens them.
    var opensPlayEdit: Bool {
        self != .ratingsReviews
    }

    /// Account rule needed to view the section.
    var requiredResource: AccountRuleResource {
        switch self {
        case .ratingsReviews:                      return .review
        case .storeListings, .tracks, .appDetails: return .apps
        }
    }
}

// MARK: - UiState

struct GooglePlayAppDetailUiState {
    var account: AccountModel
    var app: GooglePlayAppItem
    /// Default store-listing language from the cached App Details, if any.
    var defaultLanguage: String?
    var permissionDeniedMessage: String?

    /// Per-app scope of an imported account. The app list never shows an app
    /// outside it; this guards the screen itself too.
    var isAppInScope: Bool {
        account.allowsApp(bundleId: app.packageName)
    }

    let reviewSections: [GooglePlayAppDetailSection] = [.ratingsReviews]
    /// The edit-based sections, grouped under the edit side-effect footer.
    let storeSections: [GooglePlayAppDetailSection] = [.storeListings, .tracks, .appDetails]
}

// MARK: - Implementation

/// Menu of a Google Play app.
///
/// Edit side-effect mitigation: store listings, tracks and app details are read
/// through a temporary Play edit, so nothing here (nor in any background path)
/// fetches them. Each section loads only when the user opens it; this screen
/// only reads the local cache.
@MainActor
final class GooglePlayAppDetailViewModel: GooglePlayAppDetailViewModelProtocol {

    @Published var uiState: GooglePlayAppDetailUiState

    private let storage: PersistentStorable

    init(
        app: GooglePlayAppItem,
        account: AccountModel,
        storage: PersistentStorable? = nil
    ) {
        self.uiState = GooglePlayAppDetailUiState(account: account, app: app)
        self.storage = storage ?? SwiftDataStorable.shared
    }

    func load() async {
        guard uiState.isAppInScope else { return }
        let detailsCache = GooglePlayAppCacheStore<GooglePlayAppDetailsCache>(
            storage: storage,
            accountId: uiState.account.id,
            packageName: uiState.app.packageName
        )
        uiState.defaultLanguage = await detailsCache.load()?.details.defaultLanguage
    }

    func denial(for section: GooglePlayAppDetailSection) -> String? {
        GooglePlayAppSectionAccess.denialMessage(
            account: uiState.account,
            app: uiState.app,
            resource: section.requiredResource
        )
    }

    func presentDenial(_ message: String) {
        uiState.permissionDeniedMessage = message
    }
}
