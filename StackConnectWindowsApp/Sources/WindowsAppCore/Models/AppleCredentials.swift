import Foundation

public struct AppleCredentials: Codable {
    public let issuerID: String
    public let privateKeyID: String
    public let privateKey: String

    public init(issuerID: String, privateKeyID: String, privateKey: String) {
        self.issuerID = issuerID
        self.privateKeyID = privateKeyID
        self.privateKey = privateKey
    }
}
