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

    func authenticate(request: HBRequest) async throws -> AppStoreReceipt? {
        
        // 1. Get JWT from bearer authorization
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

        // 3. Verify token
        let payload: JWTPayloadData
        do {
            payload = try self.jwtSigners.verify(jwtToken, as: JWTPayloadData.self)
        } catch {
            request.logger.debug("couldn't verify JWT token")
            throw HBHTTPError(.unauthorized)
        }

        // TODO: track users
        // 4. If we want to track usage per user,
        
        // 5. Return an empty receipt for now
        return AppStoreReceipt()
        
        /*
        // check if user exists and return if it exists
        if let existingUser = try await User.query(on: request.db)
            .filter(\.$name == payload.subject.value)
            .first() {
            return existingUser
        }

        // if user doesn't exist then JWT was created by a another service and we should create a user
        // for it, with no associated password
        let user = User(id: nil, name: payload.subject.value, passwordHash: nil)
        try await user.save(on: request.db)

        return user
         */
    }
}
