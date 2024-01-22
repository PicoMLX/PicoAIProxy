//
//  AppStoreController.swift
//
//
//  Created by Ronald Mannak on 1/6/24.
//

import Foundation
import Hummingbird
import JWTKit

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
    
    private func login(_ request: HBRequest) async throws -> [String: String] {
        let user = try request.authRequire(User.self)
        let payload = JWTPayloadData(
            subject: .init(value: user.id?.uuidString ?? UUID().uuidString),
            expiration: .init(value: Date(timeIntervalSinceNow: 12 * 60 * 60)) // 12 hours
        )
        return try [
            "token": self.jwtSigners.sign(payload, kid: self.kid),
        ]
    }
}



