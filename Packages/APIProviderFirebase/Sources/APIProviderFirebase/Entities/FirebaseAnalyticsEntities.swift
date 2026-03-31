import Foundation

// MARK: - Firebase Analytics Details (v1alpha)

/// Response from `GET v1alpha/projects/{projectId}/analyticsDetails`
public struct FirebaseAnalyticsDetailsResponse: Decodable {
    public let analyticsProperty: AnalyticsProperty?
    public let streamId: String?

    public struct AnalyticsProperty: Decodable {
        /// The Google Analytics property ID (numeric, e.g. "123456789")
        public let id: String?
        public let displayName: String?
    }
}

// MARK: - Analytics Data API (analyticsdata.googleapis.com)

/// Request body for `POST /v1beta/properties/{propertyId}:runReport`
public struct RunReportRequest: Encodable {
    public let dimensions: [Dimension]?
    public let metrics: [Metric]
    public let dateRanges: [DateRange]
    public let orderBys: [OrderBy]?
    public let limit: Int?
    public let keepEmptyRows: Bool?

    public init(
        dimensions: [Dimension]? = nil,
        metrics: [Metric],
        dateRanges: [DateRange],
        orderBys: [OrderBy]? = nil,
        limit: Int? = nil,
        keepEmptyRows: Bool? = nil
    ) {
        self.dimensions = dimensions
        self.metrics = metrics
        self.dateRanges = dateRanges
        self.orderBys = orderBys
        self.limit = limit
        self.keepEmptyRows = keepEmptyRows
    }

    public struct Dimension: Encodable {
        public let name: String
        public init(name: String) { self.name = name }
    }

    public struct Metric: Encodable {
        public let name: String
        public init(name: String) { self.name = name }
    }

    public struct DateRange: Encodable {
        public let startDate: String
        public let endDate: String
        public init(startDate: String, endDate: String) {
            self.startDate = startDate
            self.endDate = endDate
        }
    }

    public struct OrderBy: Encodable {
        public let dimension: DimensionOrderBy?
        public let desc: Bool?
        public init(dimension: DimensionOrderBy? = nil, desc: Bool? = nil) {
            self.dimension = dimension
            self.desc = desc
        }
        public struct DimensionOrderBy: Encodable {
            public let dimensionName: String
            public init(dimensionName: String) { self.dimensionName = dimensionName }
        }
    }
}

/// Response from `POST /v1beta/properties/{propertyId}:runReport`
public struct RunReportResponse: Decodable {
    public let dimensionHeaders: [DimensionHeader]?
    public let metricHeaders: [MetricHeader]?
    public let rows: [Row]?
    public let rowCount: Int?

    public struct DimensionHeader: Decodable {
        public let name: String?
    }

    public struct MetricHeader: Decodable {
        public let name: String?
        public let type: String?
    }

    public struct Row: Decodable {
        public let dimensionValues: [DimensionValue]?
        public let metricValues: [MetricValue]?
    }

    public struct DimensionValue: Decodable {
        public let value: String?
    }

    public struct MetricValue: Decodable {
        public let value: String?
    }
}
