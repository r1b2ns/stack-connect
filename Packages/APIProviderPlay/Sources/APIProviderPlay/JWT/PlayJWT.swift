import Foundation
import _CryptoExtras

// MARK: - Google JWT Header

struct GoogleJWTHeader: Encodable {
    let alg = "RS256"
    let typ = "JWT"
    let kid: String
}

// MARK: - Google JWT Claims

struct GoogleJWTClaims: Encodable {
    let iss: String
    let scope: String
    let aud: String
    let iat: Int
    let exp: Int
}

// MARK: - Play JWT

struct PlayJWT {

    let configuration: PlayConfiguration

    func signedAssertion() throws -> String {
        let now = Int(Date().timeIntervalSince1970)

        let header = GoogleJWTHeader(kid: configuration.serviceAccount.privateKeyId)
        let claims = GoogleJWTClaims(
            iss: configuration.serviceAccount.clientEmail,
            scope: configuration.scopes.joined(separator: " "),
            aud: configuration.serviceAccount.tokenUri,
            iat: now,
            exp: now + Int(configuration.expirationDuration)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let headerBase64 = try encoder.encode(header).base64URLEncoded()
        let claimsBase64 = try encoder.encode(claims).base64URLEncoded()
        let signingInput = "\(headerBase64).\(claimsBase64)"

        guard let inputData = signingInput.data(using: .utf8) else {
            throw PlayAuthError.invalidJWTPayload
        }

        // Sign with RS256 (RSASSA-PKCS1-v1_5 over SHA-256). The `DataProtocol` overload
        // hashes `inputData` with SHA-256 before signing, matching the JWT RS256 spec.
        let signature: _RSA.Signing.RSASignature
        do {
            signature = try configuration.privateKey.signature(
                for: inputData,
                padding: .insecurePKCS1v1_5
            )
        } catch {
            throw PlayAuthError.signingFailed(error)
        }

        let signatureBase64 = signature.rawRepresentation.base64URLEncoded()
        return "\(signingInput).\(signatureBase64)"
    }
}

// MARK: - Base64URL

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}
