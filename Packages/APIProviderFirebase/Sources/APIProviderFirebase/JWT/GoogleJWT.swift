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
    let iss: String      // client_email
    let scope: String    // space-separated scopes
    let aud: String      // token_uri
    let iat: Int         // issued at (epoch)
    let exp: Int         // expiration (epoch)
}

// MARK: - Google JWT

/// Creates and signs JWTs for Google Service Account authentication (RS256).
struct GoogleJWT {

    let configuration: FirebaseConfiguration

    /// Creates a signed JWT assertion for exchanging with Google OAuth2.
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
            throw FirebaseAuthError.invalidJWTPayload
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
            throw FirebaseAuthError.signingFailed(error)
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
