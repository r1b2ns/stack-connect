import Foundation

public struct FirebaseCredentials: Codable {
    public let serviceAccountJSON: String

    public init(serviceAccountJSON: String) {
        self.serviceAccountJSON = serviceAccountJSON
    }
}
