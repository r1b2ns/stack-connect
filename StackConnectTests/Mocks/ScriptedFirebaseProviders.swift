import Foundation
import APIProviderFirebase
@testable import StackConnect

/// A `RequestExecutor` answering every Firebase request from `handler`, and
/// recording each request (with its `Authorization` header) in order.
final class ScriptedFirebaseExecutor: RequestExecutor, @unchecked Sendable {

    typealias Handler = @Sendable (URLRequest) -> (status: Int, json: String)

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var _handler: Handler

    init(handler: @escaping Handler = { _ in (200, "{}") }) {
        _handler = handler
    }

    var handler: Handler {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    /// The bearer tokens sent, in order.
    var bearerTokens: [String] {
        requests.compactMap { $0.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") }
    }

    func execute(_ urlRequest: URLRequest, completion: @escaping (Result<Response<Data>, Error>) -> Void) {
        let handler = lock.withLock {
            _requests.append(urlRequest)
            return _handler
        }
        let answer = handler(urlRequest)
        completion(.success(Response(requestURL: urlRequest.url, statusCode: answer.status, data: Data(answer.json.utf8))))
    }

    /// Google's 403 for a token without the needed scope.
    static let scopeInsufficientJSON = #"""
    {"error": {"code": 403, "status": "PERMISSION_DENIED", "message": "Request had insufficient authentication scopes.",
     "details": [{"@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}
    """#

    /// Google's 403 for an API disabled in the consumer project.
    static let serviceDisabledJSON = #"""
    {"error": {"code": 403, "status": "PERMISSION_DENIED", "message": "API has not been used in project 123 before or it is disabled.",
     "details": [{"@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "SERVICE_DISABLED",
                  "metadata": {"service": "analyticsdata.googleapis.com", "consumer": "projects/123",
                               "activationUrl": "https://console.developers.google.com/apis/api/analyticsdata.googleapis.com/overview?project=123"}}]}}
    """#

    static let unauthorizedJSON = #"{"error": {"code": 401, "status": "UNAUTHENTICATED"}}"#
}

/// `FirebaseProviderMaking` whose providers send through one scripted
/// executor: a service account gets a fixed bearer token, a Google sign-in
/// login its real `GoogleSignInRequestAuthenticator`.
struct ScriptedFirebaseProviderFactory: FirebaseProviderMaking {

    let executor: ScriptedFirebaseExecutor

    func makeProvider(configuration: FirebaseConfiguration) -> APIProviderFirebase {
        APIProviderFirebase(configuration: configuration, requestExecutor: executor, authenticator: FakeFirebaseAuthenticator())
    }

    func makeProvider(authenticator: RequestAuthenticating) -> APIProviderFirebase {
        APIProviderFirebase(authenticator: authenticator, requestExecutor: executor)
    }
}

/// Fixtures for the Firebase screens of a "Sign in with Google" account.
@MainActor
enum GoogleSignInFirebaseFixtures {

    static let loginId = "user-1"
    static let email = "dev@example.com"

    static func account(id: String = "firebase-google") -> AccountModel {
        AccountModel(id: id, name: "Firebase (Google)", providerType: .firebase, authMethod: .googleSignIn)
    }

    static let project = FirebaseProjectModel(id: "demo-project", displayName: "Demo", projectId: "demo-project")

    /// Stores the account's credentials (login reference only).
    static func storeCredentials(for account: AccountModel, in keychain: KeyStorable, loginId: String = loginId) {
        keychain.setObject(FirebaseCredentials(googleLoginId: loginId), forKey: "credentials.\(account.id)")
    }

    /// A Google auth mock knowing the login with `extraScopes` on top of the sign-in set.
    static func auth(extraScopes: [String] = []) -> MockGoogleAuthService {
        let auth = MockGoogleAuthService()
        auth.logins[loginId] = GoogleLogin(loginId: loginId, email: email, grantedScopes: Set(GoogleOAuthScope.signIn + extraScopes))
        return auth
    }

    /// What `requestAdditionalScopes` / `reauthenticate` return.
    static func result(scopes: [String]) -> GoogleSignInResult {
        GoogleSignInResult(
            login: GoogleLogin(loginId: loginId, email: email, grantedScopes: Set(scopes)),
            requestedScopes: scopes,
            missingScopes: [],
            isNewLogin: false
        )
    }
}
