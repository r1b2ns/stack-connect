import Foundation

private let analyticsDataBaseURL = URL(string: "https://analyticsdata.googleapis.com")!

// MARK: - Analytics Data API property

/// Access the Google Analytics Data API for a specific property.
public struct AnalyticsDataProperty {
    public let path: String

    /// Run an analytics report.
    ///
    /// `POST https://analyticsdata.googleapis.com/v1beta/properties/{propertyId}:runReport`
    public func runReport(_ body: RunReportRequest) -> Request<RunReportResponse> {
        Request(
            path: path + ":runReport",
            method: "POST",
            body: body,
            id: "analyticsData_runReport",
            customBaseURL: analyticsDataBaseURL
        )
    }
}
