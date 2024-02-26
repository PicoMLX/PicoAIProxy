//
//  File.swift
//  
//
//  Created by Ronald Mannak on 1/8/24.
//

//import FluentKit
import Foundation
import Hummingbird
import HummingbirdAuth
import JWTKit
import NIOFoundationCompat
import FluentKit

struct JWTPayloadData: JWTPayload, Equatable, HBAuthenticatable {
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case expiration = "exp"
    }

    var subject: SubjectClaim
    var expiration: ExpirationClaim
    // Define additional JWT Attributes here

    func verify(using signer: JWTSigner) throws {
        try self.expiration.verifyNotExpired()
    }
}

struct JWTAuthenticator: HBAsyncAuthenticator {
    
    let jwtSigners: JWTSigners

    init() {
        self.jwtSigners = JWTSigners()
    }

    init(_ signer: JWTSigner, kid: JWKIdentifier? = nil) {
        self.jwtSigners = JWTSigners()
        self.jwtSigners.use(signer, kid: kid)
    }

    init(jwksData: ByteBuffer) throws {
        let jwks = try JSONDecoder().decode(JWKS.self, from: jwksData)
        self.jwtSigners = JWTSigners()
        try self.jwtSigners.use(jwks: jwks)
    }

    func useSigner(_ signer: JWTSigner, kid: JWKIdentifier) {
        self.jwtSigners.use(signer, kid: kid)
    }

    func authenticate(request: HBRequest) async throws -> User? {
        
        // 1. Get JWT token from bearer authorization header
        //    If no token is present, return unauthorized error
        guard let jwtToken = request.authBearer?.token else {
            throw HBHTTPError(.unauthorized)
        }
        
        // 2. If passthrough is enabled, and OpenAI key and org is found in headers
        //    then forward request
        if let passthrough = HBEnvironment().get("allowKeyPassthrough"),
           passthrough == "1",
           let org = request.headers["OpenAI-Organization"].first,
           org.hasPrefix("org-") == true,
           jwtToken.hasPrefix("sk-") == true {
            return nil
        }

        // 3. Verify token is a valid token created by SwiftOpenAIProxy
        //    Fetch user from database
        let payload = try self.jwtSigners.verify(jwtToken, as: JWTPayloadData.self).subject.value
        let appAccountToken = UUID(uuidString: payload)
        
        let user = try await User.query(on: request.db)
            .filter(\.$appAccountToken == appAccountToken)
            .first()
        guard let user = user else {
            request.logger.error("User \(appAccountToken?.uuidString ?? "unkown") not found in database. Token: \(jwtToken)")
            throw HBHTTPError(.unauthorized)
        }
        return user
    }
}
