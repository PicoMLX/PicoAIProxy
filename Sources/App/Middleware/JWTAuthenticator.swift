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

    init(_ signer: JWTSigner, kid: JWKIdentifier) {
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
            request.logger.error("No jwtToken found")
            throw HBHTTPError(.unauthorized)
        }
        
        // 2. If passthrough is enabled, and OpenAI key and org is found in headers
        //    then forward request
        if let passthrough = HBEnvironment().get("allowKeyPassthrough"),
           passthrough == "1",
           let org = request.headers["OpenAI-Organization"].first,
           org.hasPrefix("org-") == true,
           jwtToken.hasPrefix("sk-") == true {
            request.logger.info("OpenAI API key Passthrough")
            return nil
        }

        // 3. Verify token is a valid token created by SwiftOpenAIProxy
        let payload: String
        let appAccountToken: UUID?
        do {
            payload = try self.jwtSigners.verify(jwtToken, as: JWTPayloadData.self).subject.value
            appAccountToken = UUID(uuidString: payload)
        } catch {
            request.logger.error("Invalid jwtToken received: \(jwtToken)")
            throw HBHTTPError(.unauthorized)
        }
                    
        // 4. See if user is in database
        guard let user = try await User.query(on: request.db)
            .filter(\.$appAccountToken == appAccountToken)
            .first() else {
            
            // The user has a valid jwtToken but isn't in the database
            // (This can happen after the server restarted)
            // Ask user to re-authenticate
            request.logger.error("User with app account token \(appAccountToken?.uuidString ?? "anon") not found in database")
            throw HBHTTPError(.proxyAuthenticationRequired)
        }
                
        // 5. Return user
        request.logger.info("Verified user with app account token \(user.appAccountToken?.uuidString ?? "anon")")
        return user
    }
}
