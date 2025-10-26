//
//  AppStoreController.swift
//
//
//  Created by Ronald Mannak on 1/6/24.
//

import FluentKit
import Foundation
import Hummingbird
<<<<<<< Updated upstream
import HummingbirdAuth
=======
import HummingbirdFluent
>>>>>>> Stashed changes
import JWTKit

<<<<<<< Updated upstream
struct AppStoreController<Context: AuthRequestContext> {
    
    let jwtSigners: JWTSigners
    let kid: JWKIdentifier

    
    /// Add routes for /appstore
    func addRoutes(to group: RouterGroup<Context>) {
        
        // Set app store authenticator that returns valid User instance
        // If the setup fails because the environment variables aren't set,
        // calls will be forwarded to an error message
        let appStoreAuthenticator: AppStoreAuthenticator
        do {
            appStoreAuthenticator = try AppStoreAuthenticator()
        } catch {
            group
                .post("/", use: incorrectSetup)
=======
struct AppStoreController {
    let fluent: Fluent
    let jwtSigners: JWTSigners
    let kid: JWKIdentifier

    func addRoutes(
        to group: RouterGroup<ProxyRequestContext>,
        authenticator: AppStoreAuthenticator?
    ) {
        guard let authenticator else {
            group.post("/", use: incorrectSetup)
>>>>>>> Stashed changes
            return
        }

        group
            .add(middleware: authenticator)
            .post("/", use: login)
    }
<<<<<<< Updated upstream
    
    @Sendable private func incorrectSetup(_ request: Request, context: Context) async throws -> EditedResponse<UserResponse> {
        request.logger.error("Missing environment variable(s): IAPPrivateKey, IAPIssuerId, IAPKeyId, appBundleId and/or appAppleId")
        throw HBHTTPError(.internalServerError, message: "IAPPrivateKey, IAPIssuerId, IAPKeyId and/or appBundleId environment variables not set")
=======

    @Sendable
    private func incorrectSetup(_ request: Request, context: ProxyRequestContext) async throws -> String {
        context.logger.error("Missing environment variable(s): IAPPrivateKey, IAPIssuerId, IAPKeyId, appBundleId and/or appAppleId")
        throw HTTPError(.internalServerError, message: "IAPPrivateKey, IAPIssuerId, IAPKeyId and/or appBundleId environment variables not set")
>>>>>>> Stashed changes
    }

    @Sendable
    private func login(_ request: Request, context: ProxyRequestContext) async throws -> [String: String] {
        let user = try context.requireIdentity()
        context.logger.info("Starting login for user \(user.appAccountToken?.uuidString ?? "anon")")

        let db = fluent.db()
        if try await User.query(on: db)
            .filter(\.$appAccountToken == user.appAccountToken)
            .first() == nil {
            try await user.save(on: db)
            context.logger.info("Saved user with app account token \(user.appAccountToken?.uuidString ?? "anon")")
        }

        let payload = JWTPayloadData(
            subject: .init(value: user.appAccountToken?.uuidString ?? "NO_ACCOUNT"),
            expiration: .init(value: Date(timeIntervalSinceNow: 12 * 60 * 60))
        )

        let token = try jwtSigners.sign(payload, kid: kid)

        user.jwtToken = token
        try await user.save(on: db)

        return ["token": token]
    }
}



