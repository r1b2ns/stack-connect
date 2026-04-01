import Foundation

// MARK: - Application

public struct Application {
    public let path: String

    /// Access the edits workflow for this application.
    public var edits: Edits {
        Edits(path: path + "/edits")
    }
}

// MARK: - Edits

public struct Edits {
    public let path: String

    /// Create a new edit.
    ///
    /// `POST v3/applications/{packageName}/edits`
    ///
    /// Returns an `AppEdit` with the edit ID, which is required for subsequent calls.
    public func insert() -> Request<AppEdit> {
        Request(
            path: path,
            method: "POST",
            id: "edits_insert"
        )
    }

    /// Get an existing edit.
    ///
    /// `GET v3/applications/{packageName}/edits/{editId}`
    public func get(editId: String) -> Request<AppEdit> {
        Request(
            path: path + "/\(editId)",
            method: "GET",
            id: "edits_get"
        )
    }

    /// Commit an edit, making its changes live.
    ///
    /// `POST v3/applications/{packageName}/edits/{editId}:commit`
    public func commit(editId: String) -> Request<AppEdit> {
        Request(
            path: path + "/\(editId):commit",
            method: "POST",
            id: "edits_commit"
        )
    }

    /// Delete an edit.
    ///
    /// `DELETE v3/applications/{packageName}/edits/{editId}`
    public func delete(editId: String) -> Request<Void> {
        Request(
            path: path + "/\(editId)",
            method: "DELETE",
            id: "edits_delete"
        )
    }

    /// Access app details within an edit.
    public func details(editId: String) -> EditDetails {
        EditDetails(path: path + "/\(editId)/details")
    }

    /// Access store listings within an edit.
    public func listings(editId: String) -> EditListings {
        EditListings(path: path + "/\(editId)/listings")
    }

    /// Access tracks within an edit.
    public func tracks(editId: String) -> EditTracks {
        EditTracks(path: path + "/\(editId)/tracks")
    }
}

// MARK: - Edit Details

public struct EditDetails {
    public let path: String

    /// Get the app details.
    ///
    /// `GET v3/applications/{packageName}/edits/{editId}/details`
    public func get() -> Request<AppDetails> {
        Request(path: path, method: "GET", id: "details_get")
    }
}

// MARK: - Edit Listings

public struct EditListings {
    public let path: String

    /// List all store listings.
    ///
    /// `GET v3/applications/{packageName}/edits/{editId}/listings`
    public func list() -> Request<ListingsListResponse> {
        Request(path: path, method: "GET", id: "listings_list")
    }

    /// Get a specific listing by language.
    ///
    /// `GET v3/applications/{packageName}/edits/{editId}/listings/{language}`
    public func get(language: String) -> Request<Listing> {
        Request(path: path + "/\(language)", method: "GET", id: "listings_get")
    }
}

// MARK: - Edit Tracks

public struct EditTracks {
    public let path: String

    /// List all tracks (production, beta, alpha, internal, etc.)
    ///
    /// `GET v3/applications/{packageName}/edits/{editId}/tracks`
    public func list() -> Request<TracksListResponse> {
        Request(path: path, method: "GET", id: "tracks_list")
    }

    /// Get a specific track by name.
    ///
    /// `GET v3/applications/{packageName}/edits/{editId}/tracks/{track}`
    public func get(track: String) -> Request<Track> {
        Request(path: path + "/\(track)", method: "GET", id: "tracks_get")
    }
}

// MARK: - Reviews

public struct Reviews {
    public let path: String

    /// List all reviews.
    ///
    /// `GET v3/applications/{packageName}/reviews`
    public func list(
        maxResults: Int? = nil,
        startIndex: Int? = nil,
        token: String? = nil
    ) -> Request<ReviewsListResponse> {
        var query: [(String, String?)] = []
        if let maxResults { query.append(("maxResults", String(maxResults))) }
        if let startIndex { query.append(("startIndex", String(startIndex))) }
        if let token { query.append(("token", token)) }

        return Request(
            path: path,
            method: "GET",
            query: query.isEmpty ? nil : query,
            id: "reviews_list"
        )
    }

    /// Get a specific review.
    ///
    /// `GET v3/applications/{packageName}/reviews/{reviewId}`
    public func get(reviewId: String) -> Request<Review> {
        Request(
            path: path + "/\(reviewId)",
            method: "GET",
            id: "reviews_get"
        )
    }
}
