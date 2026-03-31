import Foundation

// MARK: - List Projects Response

/// Response from `GET v1beta1/projects`.
public struct ListFirebaseProjectsResponse: Decodable {
    /// The list of Firebase projects.
    public let results: [FirebaseProject]?

    /// Pagination token for fetching the next page.
    public let nextPageToken: String?
}

// MARK: - Firebase Project

/// Represents a Firebase project.
public struct FirebaseProject: Decodable, Identifiable {

    /// The fully qualified resource name: `projects/{projectId}`
    public let name: String?

    /// The user-assigned display name.
    public let displayName: String?

    /// The globally unique project ID.
    public let projectId: String?

    /// The project number assigned by Google.
    public let projectNumber: String?

    /// The current state of the project.
    public let state: State?

    /// The default Firebase resources associated with the project.
    public let resources: DefaultResources?

    public var id: String {
        projectId ?? name ?? UUID().uuidString
    }

    // MARK: - State

    public enum State: String, Decodable {
        case stateUnspecified = "STATE_UNSPECIFIED"
        case active = "ACTIVE"
        case deleted = "DELETED"
    }

    // MARK: - Default Resources

    public struct DefaultResources: Decodable {
        /// The default Firebase Hosting site name.
        public let hostingSite: String?

        /// The default Firebase Realtime Database URL.
        public let realtimeDatabaseInstance: String?

        /// The default Cloud Storage bucket.
        public let storageBucket: String?

        /// The default GCP resource location.
        public let locationId: String?
    }
}
