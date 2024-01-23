//
//  AppStoreController.swift
//
//
//  Created by Ronald Mannak on 1/6/24.
//

import Foundation
import Hummingbird
import JWTKit
import FluentKit

struct AppStoreController {
    
    let jwtSigners: JWTSigners
    let kid: JWKIdentifier

    /// Add routes for /appstore
    func addRoutes(to group: HBRouterGroup) {
        
        // Set app store authenticator that returns valid User instance
        // If the setup fails because the environment variables aren't set,
        // calls will be forwarded to an error message
        let appStoreAuthenticator: AppStoreAuthenticator
        do {
            appStoreAuthenticator = try AppStoreAuthenticator()
        } catch {
            group
                .post("/", use: incorrectSetup)
            return
        }
        
        group
            .add(middleware: appStoreAuthenticator)
            .post("/", use: login)
    }
    
    private func incorrectSetup(_ request: HBRequest) async throws -> String {
        request.logger.error("Missing environment variable(s): IAPPrivateKey, IAPIssuerId, IAPKeyId, appBundleId and/or appAppleId")
        throw HBHTTPError(.internalServerError, message: "IAPPrivateKey, IAPIssuerId, IAPKeyId and/or appBundleId environment variables not set")
    }

    /// Note: appAccountId can be nil. All users with an empty appAccountId
    /// will be treated as a single user
    private func login(_ request: HBRequest) async throws -> [String: String] {
        
        // 1. Fetch user from AppStoreAuthenticator middleware
        let user = try request.authRequire(User.self)
        
        // 2. If user is a new user, add user to database
        if try await User.query(on: request.db)
            .filter(\.$appAccountId == user.appAccountId)
            .first()
             == nil {
            try await user.save(on: request.db)
        }
        
        let payload = JWTPayloadData(
            subject: .init(value: user.appAccountId?.uuidString ?? "NO_ACCOUNT"),
            expiration: .init(value: Date(timeIntervalSinceNow: 12 * 60 * 60)) // 12 hours
        )
        return try [
            "token": self.jwtSigners.sign(payload, kid: self.kid),
        ]
    }
}



