import Foundation
import AppStoreConnect_Swift_SDK
import StackProtocols
import StackHomeCore
import WindowsAppCore

/// Concrete `AppleConnectionProtocol` conformance backed by the App Store
/// Connect Swift SDK (`windows-support` branch). Lives in the executable target
/// so `WindowsAppCore` stays SDK-free and fully testable.
///
/// Mirrors the shape of the iOS `AppleAccountConnection` but exposes only the
/// subset of operations required by the Windows feature set (T-W01).
///
/// Declared as an `actor` so the lazily-initialised `provider` is protected
/// from data races without requiring `@unchecked Sendable`.
actor WindowsAppleConnection: AppleConnectionProtocol {

    private let credentials: AppleCredentials
    private var provider: APIProvider?

    init(credentials: AppleCredentials) {
        self.credentials = credentials
    }

    // MARK: - Provider Bootstrap

    private func ensureProvider() throws -> APIProvider {
        if let provider { return provider }
        let configuration = try APIConfiguration(
            issuerID: credentials.issuerID,
            privateKeyID: credentials.privateKeyID,
            privateKey: credentials.privateKey
        )
        let newProvider = APIProvider(configuration: configuration)
        self.provider = newProvider
        return newProvider
    }

    // MARK: - AppleConnectionProtocol

    func validateCredentials() async throws {
        let provider = try ensureProvider()
        let request = APIEndpoint.v1.apps.get(parameters: .init(limit: 1))
        _ = try await provider.request(request)
    }

    func fetchApps() async throws -> [StackProtocols.AppInfo] {
        let provider = try ensureProvider()
        let request = APIEndpoint.v1.apps.get(
            parameters: .init(sort: [.minusname], limit: 200)
        )
        let response = try await provider.request(request)

        return response.data.map { app in
            StackProtocols.AppInfo(
                id: app.id,
                name: app.attributes?.name ?? "",
                bundleId: app.attributes?.bundleID ?? "",
                platform: nil
            )
        }
    }

    func fetchUsers() async throws -> [UserModel] {
        let provider = try ensureProvider()

        async let activeResponse = provider.request(
            APIEndpoint.v1.users.get(
                parameters: .init(
                    fieldsUsers: [
                        .firstName, .lastName, .username,
                        .roles, .allAppsVisible, .provisioningAllowed
                    ],
                    limit: 200
                )
            )
        )

        async let pendingResponse = provider.request(
            APIEndpoint.v1.userInvitations.get(
                parameters: .init(
                    fieldsUserInvitations: [
                        .firstName, .lastName, .email,
                        .roles, .allAppsVisible, .provisioningAllowed,
                        .expirationDate
                    ],
                    limit: 200
                )
            )
        )

        let active = try await activeResponse
        let pending = try await pendingResponse

        let activeUsers: [UserModel] = active.data.map { user in
            UserModel(
                id: user.id,
                firstName: user.attributes?.firstName,
                lastName: user.attributes?.lastName,
                email: user.attributes?.username,
                roles: user.attributes?.roles?.map(\.rawValue) ?? [],
                allAppsVisible: user.attributes?.isAllAppsVisible ?? false,
                provisioningAllowed: user.attributes?.isProvisioningAllowed ?? false,
                isPending: false
            )
        }

        let pendingUsers: [UserModel] = pending.data.map { inv in
            UserModel(
                id: inv.id,
                firstName: inv.attributes?.firstName,
                lastName: inv.attributes?.lastName,
                email: inv.attributes?.email,
                roles: inv.attributes?.roles?.map(\.rawValue) ?? [],
                allAppsVisible: inv.attributes?.isAllAppsVisible ?? false,
                provisioningAllowed: inv.attributes?.isProvisioningAllowed ?? false,
                isPending: true
            )
        }

        return activeUsers + pendingUsers
    }

    func fetchReviews(
        appId: String,
        sort: ReviewSortOrder,
        filterRating: [String]?,
        limit: Int,
        cursor: String?
    ) async throws -> ReviewsPage {
        let provider = try ensureProvider()

        typealias Params = APIEndpoint.V1.Apps.WithID.CustomerReviews.GetParameters

        let sortValue: [Params.Sort] = {
            switch sort {
            case .createdDateDescending: return [.minuscreatedDate]
            case .createdDateAscending:  return [.createdDate]
            case .ratingDescending:      return [.minusrating]
            case .ratingAscending:       return [.rating]
            }
        }()

        let endpoint = APIEndpoint.v1.apps.id(appId).customerReviews.get(
            parameters: .init(
                filterRating: filterRating,
                sort: sortValue,
                limit: limit,
                include: [.response]
            )
        )

        // Spike implementation: always fetches the first page regardless of
        // cursor. Full cursor-based pagination (using the SDK's pageAfter
        // mechanism or raw URL continuation) lands with the Reviews feature
        // task. The protocol surface already carries the cursor so callers
        // are pagination-ready; the concrete plumbing is the only gap.
        //
        // TODO(T-W02+): implement real cursor-based pagination.
        let response: CustomerReviewsResponse = try await provider.request(endpoint)

        let hasNext = response.links.next != nil
        let nextCursor = response.links.next

        let responsesById: [String: CustomerReviewResponseV1] = {
            var dict: [String: CustomerReviewResponseV1] = [:]
            for item in response.included ?? [] {
                dict[item.id] = item
            }
            return dict
        }()

        let reviews = response.data.map { review in
            let responseRelId = review.relationships?.response?.data?.id
            let reviewResponse = responseRelId.flatMap { responsesById[$0] }

            return CustomerReviewModel(
                id: review.id,
                rating: review.attributes?.rating ?? 0,
                title: review.attributes?.title,
                body: review.attributes?.body,
                reviewerNickname: review.attributes?.reviewerNickname,
                createdDate: review.attributes?.createdDate,
                territory: review.attributes?.territory?.rawValue,
                responseId: reviewResponse?.id,
                responseBody: reviewResponse?.attributes?.responseBody,
                responseState: reviewResponse?.attributes?.state?.rawValue,
                responseDate: reviewResponse?.attributes?.lastModifiedDate
            )
        }

        return ReviewsPage(
            reviews: reviews,
            hasNextPage: hasNext,
            cursor: nextCursor
        )
    }

    func upsertReply(
        reviewId: String,
        existingResponseId: String?,
        responseBody: String
    ) async throws {
        let provider = try ensureProvider()

        // Update path: the App Store Connect API does not expose a PATCH
        // endpoint for customer review responses. To update an existing reply,
        // delete it first and then create a fresh one.
        if let existingResponseId {
            let deleteEndpoint = APIEndpoint.v1.customerReviewResponses
                .id(existingResponseId).delete
            _ = try await provider.request(deleteEndpoint)
        }

        let body = CustomerReviewResponseV1CreateRequest(
            data: .init(
                type: .customerReviewResponses,
                attributes: .init(responseBody: responseBody),
                relationships: .init(
                    review: .init(data: .init(type: .customerReviews, id: reviewId))
                )
            )
        )

        let endpoint = APIEndpoint.v1.customerReviewResponses.post(body)
        _ = try await provider.request(endpoint)
    }

    func deleteReply(responseId: String) async throws {
        let provider = try ensureProvider()
        let endpoint = APIEndpoint.v1.customerReviewResponses.id(responseId).delete
        _ = try await provider.request(endpoint)
    }
}
