import Foundation

// MARK: - App Edit (used to read app details)

/// Response from `GET v3/applications/{packageName}/edits/{editId}`
public struct AppEdit: Decodable {
    public let id: String?
    public let expiryTimeSeconds: String?
}

// MARK: - App Details

/// Response from `GET v3/applications/{packageName}/edits/{editId}/details`
public struct AppDetails: Decodable {
    public let defaultLanguage: String?
    public let contactEmail: String?
    public let contactPhone: String?
    public let contactWebsite: String?
}

// MARK: - Listing

/// Response from `GET v3/applications/{packageName}/edits/{editId}/listings/{language}`
public struct Listing: Decodable {
    public let language: String?
    public let title: String?
    public let fullDescription: String?
    public let shortDescription: String?
    public let video: String?
}

/// Response from `GET v3/applications/{packageName}/edits/{editId}/listings`
public struct ListingsListResponse: Decodable {
    public let kind: String?
    public let listings: [Listing]?
}

// MARK: - Track

/// Response from tracks endpoint.
public struct Track: Decodable {
    public let track: String?
    public let releases: [Release]?
}

public struct Release: Decodable {
    public let name: String?
    public let versionCodes: [String]?
    public let status: String?
    public let releaseNotes: [ReleaseNote]?
    public let userFraction: Double?

    public struct ReleaseNote: Decodable {
        public let language: String?
        public let text: String?
    }
}

/// Response from listing all tracks.
public struct TracksListResponse: Decodable {
    public let kind: String?
    public let tracks: [Track]?
}

// MARK: - Review

public struct Review: Decodable, Identifiable {
    public let reviewId: String?
    public let authorName: String?
    public let comments: [Comment]?

    public var id: String { reviewId ?? UUID().uuidString }

    public struct Comment: Decodable {
        public let userComment: UserComment?
        public let developerComment: DeveloperComment?
    }

    public struct UserComment: Decodable {
        public let text: String?
        public let lastModified: Timestamp?
        public let starRating: Int?
        public let device: String?
        public let androidOsVersion: Int?
        public let appVersionCode: Int?
        public let appVersionName: String?
        public let reviewerLanguage: String?
        public let thumbsUpCount: Int?
        public let thumbsDownCount: Int?
    }

    public struct DeveloperComment: Decodable {
        public let text: String?
        public let lastModified: Timestamp?
    }

    public struct Timestamp: Decodable {
        public let seconds: String?
        public let nanos: Int?
    }
}

/// Response from listing reviews.
public struct ReviewsListResponse: Decodable {
    public let reviews: [Review]?
    public let tokenPagination: TokenPagination?
    public let pageInfo: PageInfo?
}

public struct TokenPagination: Decodable {
    public let nextPageToken: String?
    public let previousPageToken: String?
}

public struct PageInfo: Decodable {
    public let totalResults: Int?
    public let resultPerPage: Int?
    public let startIndex: Int?
}
