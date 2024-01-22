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

/// Stub for JWTAuthenticator. We're not returning anything, but need the stub to make JWTAuthenticator conform HBMiddleware
struct Stub: HBAuthenticatable {
    let string: String
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

    func authenticate(request: HBRequest) async throws -> Stub? {
        
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
//        let payload: JWTPayloadData
        do {
            let payload = try self.jwtSigners.verify(jwtToken, as: JWTPayloadData.self)
        } catch {
            request.logger.debug("couldn't verify JWT token")
            throw HBHTTPError(.unauthorized)
        }

        // 4. Token is valid, we're done.
        return nil
    }
}
